//! Compare-and-swap saves of `config.json`. The app and the CLI both write it with no daemon
//! between them, so every save checks that the file is still the one the edit started from.
//!
//! - The revision is the SHA-256 of the file's bytes; a missing file has the revision of no bytes.
//! - A save takes an exclusive `flock` on `config.json.lock`, re-reads the revision, and refuses
//!   with [`StoreError::Conflict`] if it changed. Otherwise it replaces the file atomically.
//! - A file that doesn't parse is reported, never replaced by defaults.

use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use crate::config::Config;

#[derive(Clone, Debug)]
pub struct Snapshot {
    pub config: Config,
    pub revision: String,
    pub exists: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum StoreError {
    Unreadable(String),
    /// The file exists but isn't a valid config. Carries its revision, so a later save can
    /// replace exactly that file once the person chooses to.
    Invalid {
        message: String,
        revision: String,
    },
    Conflict,
    WriteFailed(String),
}

impl std::fmt::Display for StoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StoreError::Unreadable(why) => write!(f, "The configuration file couldn't be read. {why}"),
            StoreError::Invalid { message, .. } => write!(f, "The configuration file is invalid: {message}."),
            StoreError::Conflict => f.write_str("The configuration file changed since it was loaded."),
            StoreError::WriteFailed(why) => write!(f, "The configuration file couldn't be saved. {why}"),
        }
    }
}

impl std::error::Error for StoreError {}

pub fn revision(bytes: &[u8]) -> String {
    Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}

#[derive(Clone, Debug)]
pub struct ConfigStore {
    pub path: PathBuf,
}

impl ConfigStore {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        ConfigStore { path: path.into() }
    }

    pub fn load(&self) -> Result<Snapshot, StoreError> {
        let Some(bytes) = self.read()? else {
            return Ok(Snapshot { config: Config::default(), revision: revision(&[]), exists: false });
        };
        match Config::parse(&bytes) {
            Ok(config) => Ok(Snapshot { config, revision: revision(&bytes), exists: true }),
            Err(error) => Err(StoreError::Invalid { message: error.to_string(), revision: revision(&bytes) }),
        }
    }

    pub fn current_revision(&self) -> Result<String, StoreError> {
        Ok(revision(&self.read()?.unwrap_or_default()))
    }

    /// Saves `config` if the file still has `expected` as its revision, and returns the new
    /// revision. Pass `None` only when nothing was read first.
    pub fn save(&self, config: &Config, expected: Option<&str>) -> Result<String, StoreError> {
        let bytes = config.encode();
        let write = |e: io::Error| StoreError::WriteFailed(format!("{}: {e}.", self.path.display()));
        let dir = self.path.parent().unwrap_or(Path::new("."));
        fs::create_dir_all(dir).map_err(write)?;
        let _lock = lock(&with_suffix(&self.path, ".lock")).map_err(write)?;
        if let Some(expected) = expected
            && self.current_revision()? != expected
        {
            return Err(StoreError::Conflict);
        }
        replace(&self.path, &bytes).map_err(write)?;
        Ok(revision(&bytes))
    }

    fn read(&self) -> Result<Option<Vec<u8>>, StoreError> {
        match fs::read(&self.path) {
            Ok(bytes) => Ok(Some(bytes)),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(StoreError::Unreadable(format!("{}: {e}.", self.path.display()))),
        }
    }
}

/// `path` with `suffix` appended to its file name (`config.json` → `config.json.lock`).
pub fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path.file_name().unwrap_or_default().to_os_string();
    name.push(suffix);
    path.with_file_name(name)
}

/// An exclusive advisory lock on `path`, held until the returned file is dropped.
pub fn lock(path: &Path) -> io::Result<File> {
    let file = OpenOptions::new().read(true).write(true).create(true).truncate(false).open(path)?;
    file.lock()?;
    Ok(file)
}

/// Replaces `path` with `bytes` through a temporary file in the same folder and a rename, so
/// readers see either the old file or the new one.
pub fn replace(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let dir = path.parent().unwrap_or(Path::new("."));
    let mut temp = tempfile::NamedTempFile::new_in(dir)?;
    temp.write_all(bytes)?;
    temp.as_file().sync_all()?;
    temp.persist(path).map_err(|e| e.error)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{Condition, Rule};

    fn store() -> (tempfile::TempDir, ConfigStore) {
        let dir = tempfile::tempdir().unwrap();
        let store = ConfigStore::new(dir.path().join("cfg/config.json"));
        (dir, store)
    }

    #[test]
    fn a_missing_file_loads_defaults_with_the_empty_revision() {
        let (_dir, store) = store();
        let snapshot = store.load().unwrap();
        assert!(!snapshot.exists);
        assert_eq!(snapshot.config, Config::default());
        assert_eq!(snapshot.revision, revision(b""));
    }

    #[test]
    fn a_save_from_a_stale_revision_is_refused_and_leaves_the_file_alone() {
        let (_dir, store) = store();
        let start = store.load().unwrap();
        let mut theirs = start.config.clone();
        theirs.rules.push(Rule::new(Condition::Domain, "a.com", "Default"));
        store.save(&theirs, Some(&start.revision)).unwrap();
        let on_disk = fs::read(&store.path).unwrap();

        let mut mine = start.config.clone();
        mine.default_profile = "Profile 1".into();
        assert_eq!(store.save(&mine, Some(&start.revision)), Err(StoreError::Conflict));
        assert_eq!(fs::read(&store.path).unwrap(), on_disk);
    }

    #[test]
    fn a_save_returns_the_revision_of_what_it_wrote() {
        let (_dir, store) = store();
        let config = Config { browser: "b".into(), ..Config::default() };
        let rev = store.save(&config, Some(&revision(b""))).unwrap();
        assert_eq!(rev, store.current_revision().unwrap());
        assert_eq!(store.load().unwrap().config, config);
    }

    #[test]
    fn a_malformed_file_is_reported_with_its_position_and_never_replaced() {
        let (_dir, store) = store();
        fs::create_dir_all(store.path.parent().unwrap()).unwrap();
        fs::write(&store.path, b"{\"browser\": ").unwrap();
        let Err(StoreError::Invalid { message, revision: rev }) = store.load() else {
            panic!("expected invalid")
        };
        assert!(message.contains("line 1"), "{message}");
        assert_eq!(rev, revision(b"{\"browser\": "));
        assert_eq!(fs::read(&store.path).unwrap(), b"{\"browser\": ");
    }
}
