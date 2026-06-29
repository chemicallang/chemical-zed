use std::fs;
use std::path::Path;
use zed_extension_api::{self as zed, LanguageServerId, Result};

/// The Chemical Zed extension.
///
/// # Binary resolution strategy (in order)
///
/// 1. `$CHEMICAL_LSP_PATH` — exact binary path (highest priority, for debugging)
/// 2. `$CHEMICAL_LSP_HOME` — directory containing the LSP binary
/// 3. `$PATH` (via `worktree.which`)
/// 4. Common build directories (development convenience)
/// 5. Auto-download from GitHub releases (production)
///
/// # Debug / development modes
///
/// - `$CHEMICAL_LSP_DEBUG=1` will pass `--debug` to the LSP
/// - `$CHEMICAL_LSP_PORT=<port>` connects to an already-running LSP via TCP
struct ChemicalExtension {
    cached_path: Option<String>,
}

impl ChemicalExtension {
    fn resolve_binary(
        &mut self,
        worktree: &zed::Worktree,
    ) -> Result<String> {
        if let Some(ref path) = self.cached_path {
            if fs::metadata(path).is_ok() {
                return Ok(path.clone());
            }
        }

        // 1. Exact path override (highest priority)
        if let Ok(path) = std::env::var("CHEMICAL_LSP_PATH") {
            if fs::metadata(&path).is_ok() {
                self.cached_path = Some(path.clone());
                return Ok(path);
            }
        }
        for (key, value) in worktree.shell_env() {
            if key == "CHEMICAL_LSP_PATH" {
                if fs::metadata(&value).is_ok() {
                    self.cached_path = Some(value.clone());
                    return Ok(value);
                }
            }
        }

        // 2. Directory-based lookup
        if let Ok(home) = std::env::var("CHEMICAL_LSP_HOME") {
            if let Some(bin) = Self::find_lsp_in_dir(&home) {
                let path = bin.to_string();
                self.cached_path = Some(path.clone());
                return Ok(path);
            }
        }
        for (key, value) in worktree.shell_env() {
            if key == "CHEMICAL_LSP_HOME" {
                if let Some(bin) = Self::find_lsp_in_dir(&value) {
                    let path = bin.to_string();
                    self.cached_path = Some(path.clone());
                    return Ok(path);
                }
            }
        }

        // 3. Search PATH
        for name in &["chemical-lsp", "lsp", "ChemicalLsp", "ChemicalLSP"] {
            if let Some(path) = worktree.which(name) {
                self.cached_path = Some(path.clone());
                return Ok(path);
            }
        }

        // 4. Common build directories
        let worktree_path = worktree.root_path();
        let candidate_dirs = vec![
            Path::new(&worktree_path).join("cmake-build-debug"),
            Path::new(&worktree_path).join("cmake-build-release"),
            Path::new(&worktree_path).join("build"),
            Path::new(&worktree_path).join("build/debug"),
            Path::new(&worktree_path).join("build/release"),
            Path::new(&worktree_path).join("../chemical/cmake-build-debug"),
            Path::new(&worktree_path).join("../chemical/cmake-build-release"),
            Path::new(&worktree_path).join("../chemical/build/debug"),
            Path::new(&worktree_path).join("../chemical/build/release"),
            Path::new(&worktree_path).join("chemical/cmake-build-debug"),
            Path::new(&worktree_path).join("chemical/cmake-build-release"),
        ];

        for dir in &candidate_dirs {
            if let Some(bin) = Self::find_lsp_in_dir(&dir.to_string_lossy()) {
                let path = bin.to_string();
                self.cached_path = Some(path.clone());
                return Ok(path);
            }
        }

        // 5. Auto-download from GitHub releases
        self.download_binary(worktree)
    }

    fn find_lsp_in_dir(dir: &str) -> Option<String> {
        let names = ["lsp", "chemical-lsp", "ChemicalLsp", "ChemicalLSP"];
        for name in &names {
            let candidate = Path::new(dir).join(name);
            if candidate.is_file() {
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    if let Ok(meta) = fs::metadata(&candidate) {
                        if meta.permissions().mode() & 0o111 != 0 {
                            return Some(candidate.to_string_lossy().to_string());
                        }
                    }
                }
                #[cfg(not(unix))]
                {
                    return Some(candidate.to_string_lossy().to_string());
                }
            }
        }
        for name in &["lsp.exe", "chemical-lsp.exe", "ChemicalLsp.exe", "ChemicalLSP.exe"] {
            let candidate = Path::new(dir).join(name);
            if candidate.is_file() {
                return Some(candidate.to_string_lossy().to_string());
            }
        }
        None
    }

    fn download_binary(&mut self, _worktree: &zed::Worktree) -> Result<String> {
        let (os, arch) = zed::current_platform();
        let asset_name = Self::asset_name_for_platform(os, arch)
            .ok_or_else(|| format!("unsupported platform: {:?} / {:?}", os, arch))?;

        let home = std::env::var("HOME")
            .or_else(|_| std::env::var("USERPROFILE"))
            .unwrap_or_else(|_| ".".to_string());
        let lsp_dir = Path::new(&home).join(".local/share/chemical/lsp");
        fs::create_dir_all(&lsp_dir).map_err(|e| format!("failed to create cache dir: {}", e))?;

        let zip_path = lsp_dir.join(&asset_name);

        if let Some(bin) = Self::find_lsp_in_dir(&lsp_dir.to_string_lossy()) {
            self.cached_path = Some(bin.clone());
            return Ok(bin);
        }

        let release = zed::latest_github_release(
            "chemicallang/chemical",
            zed::GithubReleaseOptions {
                require_assets: true,
                pre_release: true,
            },
        )
        .map_err(|e| format!("failed to fetch latest release: {}", e))?;

        let asset = release
            .assets
            .iter()
            .find(|a| a.name == asset_name)
            .ok_or_else(|| {
                format!(
                    "no release asset found for '{}'. Available: {:?}",
                    asset_name,
                    release.assets.iter().map(|a| &a.name).collect::<Vec<_>>()
                )
            })?;

        zed::download_file(
            &asset.download_url,
            &zip_path.to_string_lossy(),
            zed::DownloadedFileType::Zip,
        )
        .map_err(|e| format!("download failed: {}", e))?;

        if let Some(bin) = Self::find_lsp_in_dir(&lsp_dir.to_string_lossy()) {
            zed::make_file_executable(&bin).ok();
            fs::remove_file(&zip_path).ok();
            self.cached_path = Some(bin.clone());
            return Ok(bin);
        }

        Err(format!(
            "LSP binary not found after extracting '{}' in '{}'. ",
            asset_name,
            lsp_dir.display()
        ))
    }

    fn asset_name_for_platform(os: zed::Os, arch: zed::Architecture) -> Option<String> {
        let os_str = match os {
            zed::Os::Linux => "linux",
            zed::Os::Mac => "macos",
            zed::Os::Windows => "windows",
        };
        let arch_str = match arch {
            zed::Architecture::Aarch64 => "arm64",
            zed::Architecture::X8664 => "x64",
            zed::Architecture::X86 => "x86",
        };
        Some(format!("{}-{}-lsp.zip", os_str, arch_str))
    }

    fn is_debug_mode(&self) -> bool {
        matches!(std::env::var("CHEMICAL_LSP_DEBUG").as_deref(), Ok("1" | "true" | "yes"))
    }

    fn debug_port(&self) -> Option<u16> {
        std::env::var("CHEMICAL_LSP_PORT")
            .ok()
            .and_then(|v| v.parse().ok())
    }
}

impl zed::Extension for ChemicalExtension {
    fn new() -> Self {
        Self { cached_path: None }
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let binary_path = self.resolve_binary(worktree)?;
        let mut args = vec!["--stdio".to_string()];
        if self.is_debug_mode() {
            args.push("--debug".to_string());
        }

        Ok(zed::Command {
            command: binary_path,
            args,
            env: Default::default(),
        })
    }

    fn language_server_workspace_configuration(
        &mut self,
        _language_server_id: &LanguageServerId,
        _worktree: &zed::Worktree,
    ) -> Result<Option<serde_json::Value>> {
        let mut config = serde_json::Map::new();

        if let Some(port) = self.debug_port() {
            config.insert(
                "lspPort".to_string(),
                serde_json::Value::Number(port.into()),
            );
        }

        if config.is_empty() {
            Ok(None)
        } else {
            Ok(Some(serde_json::Value::Object(config)))
        }
    }

    fn language_server_initialization_options(
        &mut self,
        _language_server_id: &LanguageServerId,
        _worktree: &zed::Worktree,
    ) -> Result<Option<serde_json::Value>> {
        Ok(None)
    }
}

zed::register_extension!(ChemicalExtension);
