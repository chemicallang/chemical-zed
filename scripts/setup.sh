#!/usr/bin/env bash
# ===========================================================================
#  Chemical Zed Extension — One-Command Setup
# ===========================================================================
#  Installs Rust if missing, builds the LSP from the parent project,
#  and verifies the extension can compile.
#
#  Usage:
#    chmod +x scripts/setup.sh
#    ./scripts/setup.sh
#
#  Options:
#    --help         Show this help
#    --skip-rust    Skip Rust installation check
#    --skip-lsp     Skip LSP build
# ===========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$EXTENSION_DIR/.." && pwd)"   # assumes chemical-zed is inside the chemical repo

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

SKIP_RUST=false
SKIP_LSP=false

# ------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --help)    sed -n '/^#  Usage:/,/^$/p' "$0"; exit 0 ;;
        --skip-rust) SKIP_RUST=true ;;
        --skip-lsp)  SKIP_LSP=true ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# ------------------------------------------------------------------
# 1. Rust toolchain
# ------------------------------------------------------------------
if [ "$SKIP_RUST" = false ]; then
    if command -v rustc &>/dev/null; then
        info "Rust is already installed: $(rustc --version)"
    else
        info "Installing Rust via rustup…"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
        info "Rust installed: $(rustc --version)"
    fi

    # Ensure wasm32-wasip1 target (Zed extensions use this)
    if ! rustup target list --installed | grep -q wasm32-wasip1; then
        info "Adding wasm32-wasip1 target…"
        rustup target add wasm32-wasip1
    fi
fi

# ------------------------------------------------------------------
# 2. Check for Zed
# ------------------------------------------------------------------
if command -v zed &>/dev/null; then
    info "Zed found: $(zed --version 2>/dev/null || echo 'version unknown')"
else
    warn "Zed is not installed. Install it with:"
    warn "  curl -f https://zed.dev/install.sh | sh"
    warn "Then re-run this script."
fi

# ------------------------------------------------------------------
# 3. Build Chemical LSP (optional — for development)
# ------------------------------------------------------------------
if [ "$SKIP_LSP" = false ]; then
    if [ -f "$PROJECT_DIR/CMakeLists.txt" ]; then
        info "Building Chemical LSP (this may take a while)…"
        cd "$PROJECT_DIR"

        # Run configure if not already done
        if [ ! -d "cmake-build-debug" ]; then
            if [ -f "scripts/configure.sh" ]; then
                bash scripts/configure.sh || warn "configure.sh failed — trying manual cmake"
                mkdir -p cmake-build-debug
                cmake -S . -B cmake-build-debug -DCMAKE_BUILD_TYPE=Debug
            fi
        fi

        bash scripts/build.sh --lsp --config Debug || {
            error "LSP build failed. See SETUP.md §4 for manual instructions."
            exit 1
        }

        LSP_BINARY="$PROJECT_DIR/cmake-build-debug/ChemicalLsp"
        if [ -f "$LSP_BINARY" ]; then
            info "LSP built: $LSP_BINARY"
            echo ""
            echo "  ➜  The extension will auto-detect this binary in development mode."
            echo "     No environment variable needed!"
            echo ""
        else
            warn "LSP binary not found at expected path: $LSP_BINARY"
        fi
    else
        warn "Parent project (CMakeLists.txt) not found at $PROJECT_DIR."
        warn "Skipping LSP build."
    fi
fi

# ------------------------------------------------------------------
# 4. Verify extension compiles
# ------------------------------------------------------------------
cd "$EXTENSION_DIR"
info "Checking extension build (wasm32-wasip1 target)…"
cargo check --target wasm32-wasip1 2>&1 || {
    warn "Extension check for wasm32-wasip1 failed. Checking host target instead…"
    cargo check 2>&1 || {
        error "Extension compilation failed. Check SETUP.md for dependency guidance."
        exit 1
    }
}
info "✅ Extension compiles successfully."

# ------------------------------------------------------------------
# Done
# ------------------------------------------------------------------
echo ""
info "═══════════════════════════════════════════════════════════"
info "  Setup complete!"
info ""
info "  Next steps:"
info "  1. Open Zed → Ctrl+Shift+P → 'zed: install dev extension'"
info "     → select the '$EXTENSION_DIR' directory"
info "  2. Open a .ch file — it will auto-detect as 'Chemical'"
info "  3. The LSP binary will be auto-detected or auto-downloaded"
info "═══════════════════════════════════════════════════════════"
