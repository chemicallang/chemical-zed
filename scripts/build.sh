#!/usr/bin/env bash
# ===========================================================================
#  Build the Chemical Zed Extension
# ===========================================================================
#  Compiles the Rust extension to a WebAssembly module that Zed can load.
#
#  Usage:
#    ./scripts/build.sh [--release]
# ===========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$EXTENSION_DIR"

BUILD_FLAG=""
TARGET_DIR="target/wasm32-wasip1/debug"

if [ "${1:-}" = "--release" ]; then
    BUILD_FLAG="--release"
    TARGET_DIR="target/wasm32-wasip1/release"
fi

echo "Building extension for wasm32-wasip1 (${BUILD_FLAG:-debug})…"
cargo build --target wasm32-wasip1 $BUILD_FLAG

echo ""
echo "✅ Build complete: $EXTENSION_DIR/$TARGET_DIR/zed_chemical.wasm"
echo ""
echo "To test in Zed:"
echo "  Ctrl+Shift+P → 'zed: install dev extension' → select this directory"
