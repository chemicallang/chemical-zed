# Chemical for Zed — Setup Guide

> **Goal**: Get the Chemical LSP working inside the [Zed](https://zed.dev) editor.

---

## Table of Contents

1. [Install Rust](#1-install-rust)
2. [Install Zed Editor](#2-install-zed-editor)
3. [Build the Chemical LSP](#3-build-the-chemical-lsp)
4. [Extension Structure](#4-extension-structure)
5. [Run the Extension Locally (Dev Mode)](#5-run-the-extension-locally-dev-mode)
6. [Debugging & Logs](#6-debugging--logs)
7. [Publishing the Tree-sitter Grammar](#7-publishing-the-tree-sitter-grammar)
8. [Publishing to the Zed Registry](#8-publishing-to-the-zed-registry)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Install Rust

The Zed extension is written in Rust and compiled to WebAssembly.

```bash
# Install rustup (the Rust toolchain manager)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Follow the on-screen prompt, then reload your shell:
source "$HOME/.cargo/env"

# Verify
rustc --version
cargo --version

# Add the wasm target that Zed extensions require
rustup target add wasm32-wasip1
```

> **Note**: On Linux you may also need `build-essential`:
> ```bash
> sudo apt update && sudo apt install build-essential pkg-config libssl-dev
> ```

---

## 2. Install Zed Editor

```bash
curl -f https://zed.dev/install.sh | sh
zed --version
```

---

## 3. Build the Chemical LSP

You need C++20 support (Clang ≥ 14 or GCC ≥ 11) and CMake ≥ 3.15.

### 3.1 Set up the build environment

```bash
cd chemical
./scripts/configure.sh
./scripts/setup.sh       # Linux only (libtcc)
```

### 3.2 Build the LSP target

```bash
cd chemical

# Debug build (recommended for development):
./scripts/build.sh --lsp --config Debug

# Release build:
./scripts/build.sh --lsp --config Release
```

The binary will be at `chemical/cmake-build-debug/ChemicalLsp`.

> **Note**: The LSP must support the `--stdio` flag for Zed. See
> the previous setup guide (§3) for instructions on adding it.

### 3.3 Verify

```bash
./cmake-build-debug/ChemicalLsp --version
```

---

## 4. Extension Structure

```
chemical-zed/
├── extension.toml              # Extension manifest
├── Cargo.toml                  # Rust dependencies
├── src/
│   └── lib.rs                  # Extension logic + LSP binary resolution + auto-download
├── languages/
│   └── chemical/
│       ├── config.toml         # Language metadata (file extensions, indent, brackets)
│       ├── highlights.scm      # (from tree-sitter-chem) Syntax highlighting
│       ├── indents.scm         # Indentation rules
│       ├── brackets.scm        # Bracket matching
│       └── folds.scm           # Code folding
├── scripts/
│   ├── setup.sh                # One-command setup
│   └── build.sh                # Build the extension Wasm binary
├── LICENSE
├── README.md
└── SETUP.md                    # This file

tree-sitter-chem/              # Tree-sitter grammar (separate repo)
├── package.json
├── Cargo.toml
├── grammar.js                 # Grammar definition
├── bindings/...
└── queries/                   # .scm query files
    ├── highlights.scm
    ├── indents.scm
    ├── brackets.scm
    └── folds.scm
```

### Binary resolution strategy

The extension finds the LSP binary in this order:

1. **`$CHEMICAL_LSP_HOME`** env var (process env, then worktree env)
2. **`$PATH`** (searching for `chemical-lsp`, `lsp`, `ChemicalLsp`)
3. **Build directories** — auto-detects from:
   - `cmake-build-debug/`, `cmake-build-release/`, `build/`
   - Relative to workspace root or `../chemical/`
4. **Auto-download** — fetches the appropriate `{os}-{arch}-lsp.zip`
   asset from the latest GitHub release and caches it locally

---

## 5. Run the Extension Locally (Dev Mode)

### 5.1 Pre-flight checks

1. ✅ Chemical LSP built with `--stdio` support
2. ✅ Rust installed with `wasm32-wasip1` target
3. ✅ Zed installed

### 5.2 Install the dev extension

1. Open Zed
2. Press `Ctrl+Shift+P` → **`zed: install dev extension`**
3. Select the `chemical-zed/` directory
4. Zed will automatically compile the Rust extension and load it

Open a `.ch` file — it should auto-detect as "Chemical" and the
LSP should start automatically.

### 5.3 Rebuilding after changes

- **Rust code changes**: Re-run `zed: install dev extension`
- **LSP binary changes**: Rebuild (§3.2) and reopen a `.ch` file
- **Config changes**: Restart Zed

---

## 6. Debugging & Logs

### LSP logs

```bash
Ctrl+Shift+P → "debug: open language server logs"
```

### Extension stdout/stderr

```bash
zed --foreground
```

### Zed's own logs

```bash
cat ~/.local/share/zed/logs/zed.log
```

---

## 7. Publishing the Tree-sitter Grammar

Before publishing to the Zed registry, push the grammar to GitHub:

1. Create a repository `chemicallang/tree-sitter-chem` on GitHub
2. Push the `tree-sitter-chem/` directory contents:
   ```bash
   cd tree-sitter-chem
   git init
   git add .
   git commit -m "Initial Chemical Tree-sitter grammar"
   git remote add origin https://github.com/chemicallang/tree-sitter-chem
   git push -u origin main
   ```
3. Get the latest commit hash:
   ```bash
   git rev-parse HEAD
   ```
4. Update `chemical-zed/extension.toml`:
   ```toml
   [grammars.chem]
   repository = "https://github.com/chemicallang/tree-sitter-chem"
   commit = "<the-commit-hash>"  # ← replace HEAD with the actual hash
   ```

---

## 8. Publishing to the Zed Registry

1. **Fork** `https://github.com/zed-industries/extensions`
2. **Add your extension as a submodule**:
   ```bash
   git submodule add https://github.com/chemicallang/chemical-zed extensions/chemical
   ```
3. **Register in `extensions.toml`**:
   ```toml
   [chemical]
   submodule = "extensions/chemical"
   ```
4. **Sort extensions**: `pnpm sort-extensions`
5. **Commit and open a Pull Request**

> Zed will build the Wasm binary from your Rust source. Make sure
> `Cargo.toml` and all source files are committed.

---

## 9. Troubleshooting

### "Chemical LSP not found"

The extension should auto-detect the binary. If not:

```bash
# Check if the binary exists
ls -la chemical/cmake-build-debug/ChemicalLsp

# Or set the env var explicitly
export CHEMICAL_LSP_HOME=/path/to/chemical/cmake-build-debug
zed --foreground
```

If auto-download fails, check:
- You have internet access (GitHub API)
- The release asset naming matches: `linux-x64-lsp.zip`, `macos-arm64-lsp.zip`, etc.
- The `granted_extension_capabilities` setting allows downloads from `github.com`:
  ```json
  {
    "granted_extension_capabilities": [
      { "kind": "download_file", "host": "github.com", "path": ["**"] }
    ]
  }
  ```
  Add this to your Zed `settings.json`.

### Language not auto-detecting

- Make sure the extension is installed as a dev extension
- Check that `path_suffixes = ["ch"]` is in `config.toml`
- Restart Zed after installing the extension
- The grammar must be available (push to GitHub and update `extension.toml`)

### LSP crashes on startup

- Verify `--stdio` support is implemented in the LSP binary
- Check LSP logs: `Ctrl+Shift+P` → "debug: open language server logs"
- Run the LSP manually: `./ChemicalLsp --stdio`

### Extension not loading

```bash
cat ~/.local/share/zed/logs/zed.log | grep chemical
```

Check for compilation errors. Ensure `crate-type = ["cdylib"]` in `Cargo.toml`.
