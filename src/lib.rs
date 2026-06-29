use std::fs;
use std::path::Path;
use zed_extension_api::{self as zed, LanguageServerId, Result};

/// The Chemical Zed extension.
///
/// # Binary resolution strategy
///
/// In order of preference:
/// 1. `$CHEMICAL_LSP_HOME` (process env or worktree shell env)
/// 2. `$PATH` (via `worktree.which`)
/// 3. Common build directories (development convenience)
/// 4. Auto-download from GitHub releases (production)
struct ChemicalExtension {
    /// Path to the resolved LSP binary (cached after first lookup).
    cached_path: Option<String>,
}

impl ChemicalExtension {
    /// Locate the Chemical LSP binary, downloading it if necessary.
    fn resolve_binary(
        &mut self,
        worktree: &zed::Worktree,
    ) -> Result<String> {
        // Fast path: use cached path if still valid
        if let Some(ref path) = self.cached_path {
            if fs::metadata(path).is_ok() {
                return Ok(path.clone());
            }
        }

        // 1. Check `$CHEMICAL_LSP_HOME` from process env (most reliable)
        if let Ok(home) = std::env::var("CHEMICAL_LSP_HOME") {
            if let Some(bin) = Self::find_lsp_in_dir(&home) {
                let path = bin.to_string();
                self.cached_path = Some(path.clone());
                return Ok(path);
            }
        }

        // 2. Check `$CHEMICAL_LSP_HOME` from worktree shell env
        for (key, value) in worktree.shell_env() {
            if key == "CHEMICAL_LSP_HOME" {
                if let Some(bin) = Self::find_lsp_in_dir(&value) {
                    let path = bin.to_string();
                    self.cached_path = Some(path.clone());
                    return Ok(path);
                }
            }
        }

        // 3. Search `$PATH`
        for name in &["chemical-lsp", "lsp", "ChemicalLsp", "ChemicalLSP"] {
            if let Some(path) = worktree.which(name) {
                self.cached_path = Some(path.clone());
                return Ok(path);
            }
        }

        // 4. Check common build directories (development mode convenience)
        let worktree_path = worktree.root_path();
        let candidate_dirs = vec![
            // Relative to workspace (project root)
            Path::new(&worktree_path).join("cmake-build-debug"),
            Path::new(&worktree_path).join("cmake-build-release"),
            Path::new(&worktree_path).join("build"),
            Path::new(&worktree_path).join("build/debug"),
            Path::new(&worktree_path).join("build/release"),
            // Relative to the extension itself (../chemical/)
            Path::new(&worktree_path).join("../chemical/cmake-build-debug"),
            Path::new(&worktree_path).join("../chemical/cmake-build-release"),
            Path::new(&worktree_path).join("../chemical/build/debug"),
            Path::new(&worktree_path).join("../chemical/build/release"),
            // Common home directory paths
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

    /// Look for an LSP executable inside `dir`.
    fn find_lsp_in_dir(dir: &str) -> Option<String> {
        let names = ["lsp", "chemical-lsp", "ChemicalLsp", "ChemicalLSP"];
        for name in &names {
            let candidate = Path::new(dir).join(name);
            if candidate.is_file() {
                // Check if it's executable (Unix) or exists (Windows)
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
        // Also try with .exe extension (Windows cross-compilation)
        for name in &["lsp.exe", "chemical-lsp.exe", "ChemicalLsp.exe", "ChemicalLSP.exe"] {
            let candidate = Path::new(dir).join(name);
            if candidate.is_file() {
                return Some(candidate.to_string_lossy().to_string());
            }
        }
        None
    }

    /// Download the LSP binary from the latest GitHub release and cache it.
    fn download_binary(&mut self, _worktree: &zed::Worktree) -> Result<String> {
        let (os, arch) = zed::current_platform();
        let asset_name = Self::asset_name_for_platform(os, arch)
            .ok_or_else(|| format!("unsupported platform: {:?} / {:?}", os, arch))?;

        // Cache under the user's home directory (persists across restarts)
        let home = std::env::var("HOME")
            .or_else(|_| std::env::var("USERPROFILE")) // Windows fallback
            .unwrap_or_else(|_| ".".to_string());
        let lsp_dir = Path::new(&home).join(".local/share/chemical/lsp");
        fs::create_dir_all(&lsp_dir).map_err(|e| format!("failed to create cache dir: {}", e))?;

        let zip_path = lsp_dir.join(&asset_name);

        // Check if already downloaded (search for any known binary name)
        if let Some(bin) = Self::find_lsp_in_dir(&lsp_dir.to_string_lossy()) {
            self.cached_path = Some(bin.clone());
            return Ok(bin);
        }

        // Fetch latest release
        let release = zed::latest_github_release(
            "chemicallang/chemical",
            zed::GithubReleaseOptions {
                require_assets: true,
                pre_release: true, // include pre-releases since Chemical is in active development
            },
        )
        .map_err(|e| format!("failed to fetch latest release: {}", e))?;

        // Find the asset matching our platform
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

        // Download and extract the zip
        zed::download_file(&asset.download_url, &zip_path.to_string_lossy(), zed::DownloadedFileType::Zip)
            .map_err(|e| format!("download failed: {}", e))?;

        // Search for the binary inside the extracted directory
        if let Some(bin) = Self::find_lsp_in_dir(&lsp_dir.to_string_lossy()) {
            // Make the binary executable (does nothing on Windows)
            zed::make_file_executable(&bin).ok();
            // Clean up the zip
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

    /// Return the expected release asset name for the current OS/arch.
    ///
    /// Must match what the VS Code extension and CI publish.
    /// Format: `{os}-{arch}-lsp.zip`
    fn asset_name_for_platform(os: zed::Os, arch: zed::Architecture) -> Option<String> {
        let os_str = match os {
            zed::Os::Linux => "linux",
            zed::Os::Mac => "macos",
            zed::Os::Windows => "windows",
            _ => return None,
        };
        let arch_str = match arch {
            zed::Architecture::Aarch64 => "arm64",
            zed::Architecture::X8664 => "x64",
            zed::Architecture::X86 => "x86",
            _ => return None,
        };
        Some(format!("{}-{}-lsp.zip", os_str, arch_str))
    }
}

impl zed::Extension for ChemicalExtension {
    fn new() -> Self {
        Self { cached_path: None }
    }

    fn language_server_command(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let binary_path = self.resolve_binary(worktree)?;

        Ok(zed::Command {
            command: binary_path,
            args: vec!["--stdio".to_string()],
            env: Default::default(),
        })
    }

    fn language_server_workspace_configuration(
        &mut self,
        _language_server_id: &LanguageServerId,
        _worktree: &zed::Worktree,
    ) -> Result<Option<serde_json::Value>> {
        Ok(None)
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
