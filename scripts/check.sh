#!/usr/bin/env bash
# ===========================================================================
#  Chemical Zed Extension — Build Check & LSP Verification
# ===========================================================================
#  Usage:
#    ./scripts/check.sh [--lsp] [--release]
#
#  Options:
#    --help        Show this help
#    --lsp         Also build and verify the Chemical LSP
#    --release     Check release build instead of debug
# ===========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$EXTENSION_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

CHECK_LSP=false
RELEASE=false
EXIT_CODE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --help) sed -n '/^#  Usage:/,/^$/p' "$0"; exit 0 ;;
        --lsp)     CHECK_LSP=true ;;
        --release) RELEASE=true ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

BUILD_FLAG=""
TARGET_DIR="debug"
if [ "$RELEASE" = true ]; then
    BUILD_FLAG="--release"
    TARGET_DIR="release"
fi

# ------------------------------------------------------------------
# 0. Prerequisites
# ------------------------------------------------------------------
info "Checking prerequisites..."

if ! command -v rustc &>/dev/null; then
    error "Rust is not installed. See https://rustup.rs"
    exit 1
fi
info "  rustc $(rustc --version)"

if ! rustup target list --installed | grep -q wasm32-wasip1; then
    info "  Adding wasm32-wasip1 target..."
    rustup target add wasm32-wasip1
fi

# ------------------------------------------------------------------
# 1. Verify extension compiles (fast check)
# ------------------------------------------------------------------
info ""
info "═══════════════════════════════════════════════════════════"
info "  1. Checking extension compilation (cargo check)…"
info "═══════════════════════════════════════════════════════════"

cd "$EXTENSION_DIR"
if cargo check --target wasm32-wasip1 2>&1; then
    info "  ✅ cargo check passed"
else
    error "  ❌ cargo check failed"
    EXIT_CODE=1
fi

# ------------------------------------------------------------------
# 2. Full build (slower but produces the .wasm)
# ------------------------------------------------------------------
info ""
info "═══════════════════════════════════════════════════════════"
info "  2. Building extension wasm binary…"
info "═══════════════════════════════════════════════════════════"

if cargo build --target wasm32-wasip1 $BUILD_FLAG 2>&1; then
    WASM_PATH="$EXTENSION_DIR/target/wasm32-wasip1/$TARGET_DIR/zed_chemical.wasm"
    if [ -f "$WASM_PATH" ]; then
        WASM_SIZE=$(stat --printf="%s" "$WASM_PATH" 2>/dev/null || stat -f"%z" "$WASM_PATH" 2>/dev/null)
        info "  ✅ Build complete: $WASM_PATH ($((WASM_SIZE / 1024)) KB)"
    else
        warn "  ⚠️  Build OK but .wasm not found at expected path"
    fi
else
    error "  ❌ Build failed"
    EXIT_CODE=1
fi

# ------------------------------------------------------------------
# 3. LSP verification (if --lsp)
# ------------------------------------------------------------------
if [ "$CHECK_LSP" = true ]; then
    info ""
    info "═══════════════════════════════════════════════════════════"
    info "  3. Building & verifying Chemical LSP…"
    info "═══════════════════════════════════════════════════════════"

    if [ ! -f "$PROJECT_DIR/scripts/build.sh" ]; then
        error "  Parent chemical project not found at $PROJECT_DIR"
        error "  (scripts/build.sh missing)"
        EXIT_CODE=1
    else
        cd "$PROJECT_DIR"

        # Configure if needed
        if [ ! -d "cmake-build-debug" ]; then
            info "  Configuring CMake build..."
            if [ -f "scripts/configure.sh" ]; then
                bash scripts/configure.sh || warn "  configure.sh failed"
            fi
            mkdir -p cmake-build-debug
            (cmake -S . -B cmake-build-debug -DCMAKE_BUILD_TYPE=Debug 2>&1) || {
                warn "  cmake configure failed — LSP may not be buildable on this system"
            }
        fi

        # Build LSP
        info "  Building LSP (Debug)…"
        if bash scripts/build.sh --lsp --config Debug 2>&1; then
            LSP_BINARY="$PROJECT_DIR/cmake-build-debug/ChemicalLsp"

            if [ -f "$LSP_BINARY" ]; then
                LSP_SIZE=$(stat --printf="%s" "$LSP_BINARY" 2>/dev/null || stat -f"%z" "$LSP_BINARY" 2>/dev/null)
                info "  ✅ LSP built: $LSP_BINARY ($((LSP_SIZE / 1024)) KB)"

                # Test that --version works
                info "  Checking LSP --version…"
                if $LSP_BINARY --version 2>&1; then
                    info "  ✅ LSP --version OK"
                else
                    warn "  ⚠️  LSP --version failed (exit code $?)"
                fi

                # Quick smoke test: --stdio should start and respond
                info "  Smoke testing LSP --stdio (initialize request)…"
                INIT_MSG='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"capabilities":{},"rootUri":null}}'
                INIT_NOTIFY='{"jsonrpc":"2.0","method":"initialized","params":{}}'
                SHUTDOWN_MSG='{"jsonrpc":"2.0","id":2,"method":"shutdown","params":null}'
                EXIT_NOTIFY='{"jsonrpc":"2.0","method":"exit","params":null}'

                # Write all messages, read Content-Length responses
                LSP_OUTPUT=$(echo -e "$INIT_MSG\r\n$INIT_NOTIFY\r\n$SHUTDOWN_MSG\r\n$EXIT_NOTIFY" | \
                    timeout 5 "$LSP_BINARY" --stdio 2>/dev/null || true)

                if echo "$LSP_OUTPUT" | grep -q "Content-Length"; then
                    info "  ✅ LSP --stdio responds with valid LSP messages"
                else
                    warn "  ⚠️  LSP --stdio did not produce expected output"
                    warn "     (output: $(echo "$LSP_OUTPUT" | head -c 200))"
                fi
            else
                error "  ❌ LSP binary not found after build"
                EXIT_CODE=1
            fi
        else
            error "  ❌ LSP build failed"
            EXIT_CODE=1
        fi
    fi
fi

# ------------------------------------------------------------------
# 4. Verify language files are in place
# ------------------------------------------------------------------
info ""
info "═══════════════════════════════════════════════════════════"
info "  4. Checking language files…"
info "═══════════════════════════════════════════════════════════"

LANG_DIR="$EXTENSION_DIR/languages/chemical"
MISSING=0
for f in config.toml highlights.scm brackets.scm folds.scm indents.scm; do
    if [ -f "$LANG_DIR/$f" ]; then
        info "  ✅ $f"
    else
        warn "  ⚠️  Missing: $LANG_DIR/$f"
        MISSING=$((MISSING + 1))
    fi
done

if [ "$MISSING" -gt 0 ]; then
    warn "  $MISSING language file(s) missing (highlights/brackets/folds/indents)"
    warn "  Copy them from ../tree-sitter-chem/queries/"
fi

# ------------------------------------------------------------------
# 5. Check extension.toml validity
# ------------------------------------------------------------------
info ""
info "═══════════════════════════════════════════════════════════"
info "  5. Checking extension.toml…"
info "═══════════════════════════════════════════════════════════"

if [ -f "$EXTENSION_DIR/extension.toml" ]; then
    if grep -q '^id\s*=' "$EXTENSION_DIR/extension.toml"; then
        info "  ✅ extension.toml valid (has id)"
    else
        error "  ❌ extension.toml missing 'id' field"
        EXIT_CODE=1
    fi
else
    error "  ❌ extension.toml not found"
    EXIT_CODE=1
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
if [ "$EXIT_CODE" -eq 0 ]; then
    info "═══════════════════════════════════════════════════════════"
    info "  ✅ All checks passed!"
    info ""
    info "  Install in Zed:"
    info "    Ctrl+Shift+P → 'zed: install dev extension'"
    info "    → select '$EXTENSION_DIR'"
    info ""
    if [ "$CHECK_LSP" = true ]; then
        info "  LSP is ready. Open a .ch file to test."
    fi
    info "═══════════════════════════════════════════════════════════"
else
    error "═══════════════════════════════════════════════════════════"
    error "  ❌ Some checks failed (exit code $EXIT_CODE)"
    error "═══════════════════════════════════════════════════════════"
fi

exit $EXIT_CODE
