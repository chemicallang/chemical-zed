# Chemical for Zed

Chemical programming language support for the [Zed editor](https://zed.dev).

## Features

- **LSP integration** — code intelligence, diagnostics, completions, hover info
- **Language auto-detection** — `.ch` files automatically recognized
- **Syntax highlighting** — via Tree-sitter grammar
- **Auto-download** — LSP binary fetched from GitHub releases if not found locally
- **Development mode** — auto-detects LSP from common build directories

## Quick Start

```bash
# 1. Ensure you have Rust + wasm target
rustup target add wasm32-wasip1

# 2. Open Zed → Ctrl+Shift+P → "zed: install dev extension"
#    → select the `chemical-zed/` directory

# 3. Open a .ch file — enjoy Chemical in Zed!
```

> **Note**: The Chemical LSP binary must support `--stdio`. See `SETUP.md` §3
> for details on building the LSP with stdio support.

## Structure

| Path | Purpose |
|------|---------|
| `extension.toml` | Extension manifest |
| `src/lib.rs` | Rust extension — resolves LSP binary (env, PATH, build dirs, auto-download) |
| `languages/chemical/config.toml` | Language config (`.ch` files → Chemical) |
| `scripts/setup.sh` | One-command setup |
| `scripts/build.sh` | Build extension Wasm binary |

## Binary Resolution Order

1. `$CHEMICAL_LSP_HOME` environment variable
2. `$PATH` search
3. Common build directories (`cmake-build-debug/`, etc.)
4. Auto-download from [GitHub releases](https://github.com/chemicallang/chemical/releases)

## License

MIT
