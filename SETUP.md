# Chemical for Zed — Setup Guide

## Quick Start

```bash
# 1. Ensure Rust + wasm target
rustup target add wasm32-wasip1

# 2. Build & check
./scripts/check.sh

# 3. Open Zed → Ctrl+Shift+P → "zed: install dev extension"
#    → select the chemical-zed/ directory

# 4. Open a .ch or .mod file
```

## Debug Binary Configuration

Set any of these env vars before launching Zed:

| Env Var | Purpose |
|---------|---------|
| `CHEMICAL_LSP_PATH` | Exact path to LSP binary (highest priority) |
| `CHEMICAL_LSP_HOME` | Directory containing LSP binary |
| `CHEMICAL_LSP_DEBUG=1` | Passes `--debug` flag to LSP |
| `CHEMICAL_LSP_PORT=<n>` | Port for LSP (passed via workspace config) |

Example:
```bash
CHEMICAL_LSP_PATH=/path/to/ChemicalLsp zed
```

## Grammar

The grammar references a local git repo (`../tree-sitter-chem`). For
publishing, update `extension.toml` to point to the GitHub URL.

## File Structure

```
chemical-zed/
├── extension.toml           # Manifest + grammar + LSP config
├── Cargo.toml               # Rust crate (compiled to .wasm)
├── src/lib.rs               # Extension logic + binary resolution
├── languages/chemical/
│   ├── config.toml          # Language config (.ch + .mod)
│   ├── highlights.scm       # Syntax highlighting
│   ├── brackets.scm         # Bracket matching
│   ├── folds.scm            # Code folding
│   └── indents.scm          # Indentation
├── icons/                   # File type icons
│   ├── chemical.svg         # .ch files
│   └── chemical-mod.svg     # .mod files
├── scripts/
│   ├── check.sh             # Build check + optional LSP test
│   ├── build.sh             # Compile extension to .wasm
│   └── setup.sh             # One-command setup
├── .gitignore
├── README.md
└── SETUP.md
```
