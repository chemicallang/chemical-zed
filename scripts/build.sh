#!/usr/bin/env bash
# ===========================================================================
#  Build the Chemical Zed Extension
# ===========================================================================
#  Compiles the Rust extension to a WebAssembly module that Zed can load.
#
#  Usage:
#    ./scripts/build.sh [--release] [--check-only]
#
#  Options:
#    --release     Build in release mode (smaller .wasm, slower compile)
#    --check-only  Only run cargo check (fast, no .wasm produced)
#    --help        Show this help
# ===========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$EXTENSION_DIR"

RELEASE=false
CHECK_ONLY=false

while [ $# -gt 0 ]; do
    case "$1" in
        --help) sed -n '/^#  Usage:/,/^$/p' "$0"; exit 0 ;;
        --release)    RELEASE=true ;;
        --check-only) CHECK_ONLY=true ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

BUILD_FLAG=""
TARGET_DIR="target/wasm32-wasip1/debug"
if [ "$RELEASE" = true ]; then
    BUILD_FLAG="--release"
    TARGET_DIR="target/wasm32-wasip1/release"
fi

echo "Building extension for wasm32-wasip1 (${BUILD_FLAG:-debug})…"

if [ "$CHECK_ONLY" = true ]; then
    cargo check --target wasm32-wasip1 $BUILD_FLAG
    echo ""
    echo "✅ cargo check passed"
else
    # Use cargo's incremental compilation — keep CARGO_BUILD_JOBS at your CPU count
    cargo build --target wasm32-wasip1 $BUILD_FLAG

    echo ""
    echo "✅ Build complete: $EXTENSION_DIR/$TARGET_DIR/zed_chemical.wasm"
    echo ""
    echo "To test in Zed:"
    echo "  Ctrl+Shift+P → 'zed: install dev extension' → select this directory"
fi
