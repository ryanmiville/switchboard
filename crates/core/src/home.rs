//! The home folder every path hangs off. Binaries build it from `$HOME`; tests from a temporary
//! folder.

use std::path::{Path, PathBuf};

use crate::identity;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Home(PathBuf);

impl Home {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Home(path.into())
    }

    pub fn path(&self) -> &Path {
        &self.0
    }

    pub fn join(&self, relative: impl AsRef<Path>) -> PathBuf {
        self.0.join(relative)
    }

    /// `~/.config/switchboard-rs/config.json`.
    pub fn config_file(&self) -> PathBuf {
        self.join(".config").join(identity::DIR_NAME).join("config.json")
    }

    /// `~/.local/state/switchboard-rs/history.jsonl`.
    pub fn history_file(&self) -> PathBuf {
        self.join(".local/state").join(identity::DIR_NAME).join("history.jsonl")
    }

    /// The Swift app's config, for importing.
    pub fn swift_config_file(&self) -> PathBuf {
        self.join(identity::SWIFT_CONFIG)
    }

    /// Expands a leading `~` or `~/`.
    pub fn expand(&self, path: &str) -> PathBuf {
        match path.strip_prefix('~') {
            Some("") => self.0.clone(),
            Some(rest) if rest.starts_with('/') => self.0.join(&rest[1..]),
            _ => PathBuf::from(path),
        }
    }
}

/// The parts of the process environment the platform crates need, read once by each binary's
/// `main` so library code never reads the environment itself.
#[derive(Clone, Debug, Default)]
pub struct Env {
    /// `$PATH`, split.
    pub path: Vec<PathBuf>,
    /// `$XDG_DATA_DIRS`, split; empty when unset.
    pub xdg_data_dirs: Vec<PathBuf>,
    /// `$SWITCHBOARD_RS_APPLICATIONS`, split: when set, the only folders searched for browsers.
    /// Tests and scenes set it so they never see the machine's real browsers.
    pub app_dirs: Option<Vec<PathBuf>>,
    /// The other variables Switchboard reads, by name. See [`Env::NAMES`].
    pub vars: std::collections::BTreeMap<String, String>,
}

impl Env {
    /// Variables kept in [`Env::vars`].
    pub const NAMES: &[&str] = &[
        "SWITCHBOARD_RS_CONFIG",
        "SWITCHBOARD_RS_HISTORY",
        "CLAUDE_CONFIG_DIR",
        "CODEX_HOME",
        "XDG_CONFIG_HOME",
    ];

    #[expect(clippy::disallowed_methods, reason = "the one place the environment is read")]
    pub fn from_process() -> (Option<Home>, Env) {
        let split =
            |name: &str| std::env::var_os(name).map(|v| std::env::split_paths(&v).collect::<Vec<_>>());
        let home = std::env::var_os("HOME").filter(|h| !h.is_empty()).map(Home::new);
        let vars = Self::NAMES
            .iter()
            .filter_map(|n| std::env::var(n).ok().filter(|v| !v.is_empty()).map(|v| ((*n).to_owned(), v)))
            .collect();
        let env = Env {
            path: split("PATH").unwrap_or_default(),
            xdg_data_dirs: split("XDG_DATA_DIRS").unwrap_or_default(),
            app_dirs: split("SWITCHBOARD_RS_APPLICATIONS"),
            vars,
        };
        (home, env)
    }

    pub fn var(&self, name: &str) -> Option<&str> {
        self.vars.get(name).map(String::as_str)
    }
}
