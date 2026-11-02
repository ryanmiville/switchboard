//! A log of the links Switchboard opened, so an agent can find "that last link" without the person
//! pasting it. Append-only JSON Lines, newest last, trimmed to the newest [`KEEP`] entries.
//!
//! Recording is best effort: [`record`] never fails a link. A failed write is kept in
//! `history.jsonl.error` for `doctor` and cleared by the next success.

use std::fs::{self, OpenOptions};
use std::hash::{BuildHasher, Hasher};
use std::io::{self, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::config::{Condition, Config, Destination};
use crate::platform::Browsers;
use crate::profiles;
use crate::store::{lock, replace, with_suffix};
use crate::time::Timestamp;

pub const KEEP: usize = 200;
pub const TRIM_AT: usize = 400;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Source {
    Rule,
    Default,
    Picker,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Outcome {
    Launched,
    Failed,
}

/// The rule as it was when the link opened; positions change later.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RuleSnapshot {
    /// 1-based, as `rules list` shows it.
    pub index: usize,
    pub condition: Condition,
    pub value: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    pub id: String,
    /// RFC 3339, UTC.
    pub time: String,
    pub url: String,
    pub source: Source,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rule: Option<RuleSnapshot>,
    pub browser: String,
    pub profile: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile_name: Option<String>,
    pub result: Outcome,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl Entry {
    pub fn timestamp(&self) -> Option<Timestamp> {
        Timestamp::parse(&self.time)
    }

    pub fn redacted_url(&self) -> String {
        redact(&self.url)
    }
}

/// Eight random lowercase hex characters.
pub fn new_id() -> String {
    let mut hasher = std::collections::hash_map::RandomState::new().build_hasher();
    hasher.write_u128(std::time::Instant::now().elapsed().as_nanos());
    format!("{:08x}", hasher.finish() as u32)
}

/// Replaces the query, fragment and user info, which can carry tokens from magic links and OAuth
/// callbacks: `https://u:p@x.com/a?t=1#f` → `https://…@x.com/a?…#…`.
pub fn redact(url: &str) -> String {
    let mut base = url;
    let mut suffix = String::new();
    if let Some(hash) = base.find('#') {
        suffix = if hash + 1 < base.len() { "#…".into() } else { "#".into() };
        base = &base[..hash];
    }
    if let Some(question) = base.find('?') {
        suffix = format!("{}{suffix}", if question + 1 < base.len() { "?…" } else { "?" });
        base = &base[..question];
    }
    let mut out = base.to_owned();
    if let Some(start) = out.find("://").map(|i| i + 3) {
        let end = out[start..].find('/').map_or(out.len(), |i| start + i);
        if let Some(at) = out[start..end].rfind('@') {
            out.replace_range(start..start + at, "…");
        }
    }
    out + &suffix
}

#[derive(Clone, Debug)]
pub struct HistoryStore {
    pub path: PathBuf,
}

impl HistoryStore {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        HistoryStore { path: path.into() }
    }

    pub fn error_path(&self) -> PathBuf {
        with_suffix(&self.path, ".error")
    }

    fn lock_path(&self) -> PathBuf {
        with_suffix(&self.path, ".lock")
    }

    /// The newest [`KEEP`] entries, newest first. Lines that don't parse are skipped, so one bad
    /// line doesn't hide the rest.
    pub fn entries(&self) -> io::Result<Vec<Entry>> {
        let text = match fs::read_to_string(&self.path) {
            Ok(text) => text,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(e) => return Err(e),
        };
        Ok(text.lines().rev().filter_map(|l| serde_json::from_str(l).ok()).take(KEEP).collect())
    }

    /// Appends one entry, creating the folder (0700) and file (0600) when needed.
    pub fn append(&self, entry: &Entry) -> io::Result<()> {
        let dir = self.path.parent().unwrap_or(Path::new("."));
        if !dir.exists() {
            if let Some(parent) = dir.parent() {
                fs::create_dir_all(parent)?;
            }
            match fs::DirBuilder::new().mode(0o700).create(dir) {
                Err(e) if e.kind() != io::ErrorKind::AlreadyExists => return Err(e),
                _ => {}
            }
        }
        let mut line = serde_json::to_vec(entry).map_err(io::Error::other)?;
        line.push(b'\n');
        {
            let _lock = lock(&self.lock_path())?;
            let mut file = OpenOptions::new().create(true).append(true).mode(0o600).open(&self.path)?;
            file.write_all(&line)?;
            self.trim()?;
        }
        // Best effort: a stale error note only makes `doctor` report an old failure.
        fs::remove_file(self.error_path()).ok();
        Ok(())
    }

    /// Deletes the history and returns how many entries it had.
    pub fn clear(&self) -> io::Result<usize> {
        let count = self.entries().map_or(0, |e| e.len());
        if self.path.exists() {
            let _lock = lock(&self.lock_path())?;
            fs::remove_file(&self.path)?;
        }
        match fs::remove_file(self.error_path()) {
            Err(e) if e.kind() != io::ErrorKind::NotFound => return Err(e),
            _ => {}
        }
        Ok(count)
    }

    pub fn last_write_error(&self) -> Option<String> {
        let text = fs::read_to_string(self.error_path()).ok()?;
        let text = text.trim();
        (!text.is_empty()).then(|| text.to_owned())
    }

    pub fn record_write_error(&self, error: &io::Error, at: Timestamp) {
        // Best effort: there is nowhere else to report a failure to record a failure.
        fs::write(self.error_path(), format!("{} {error}\n", at.rfc3339())).ok();
    }

    fn trim(&self) -> io::Result<()> {
        let text = fs::read_to_string(&self.path)?;
        let lines: Vec<&str> = text.lines().collect();
        if lines.len() <= TRIM_AT {
            return Ok(());
        }
        let mut kept = lines[lines.len() - KEEP..].join("\n");
        kept.push('\n');
        replace(&self.path, kept.as_bytes())?;
        fs::set_permissions(&self.path, fs::Permissions::from_mode(0o600))
    }
}

/// Where a link's destination came from.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Origin {
    /// The rule at this 0-based index in the config used.
    Rule(usize),
    Default,
    Picker,
}

/// What [`record`] needs about one opened link.
pub struct Opened<'a> {
    pub url: &'a str,
    pub destination: &'a Destination,
    pub origin: Origin,
    pub config: &'a Config,
    pub error: Option<String>,
    pub now: Timestamp,
}

/// Records a link if history is enabled. Never fails the link: a write failure is returned for
/// logging and kept for `doctor`.
pub fn record(store: &HistoryStore, browsers: &dyn Browsers, opened: Opened<'_>) -> Option<io::Error> {
    if !opened.config.history_enabled() {
        return None;
    }
    let (source, rule) = match opened.origin {
        Origin::Rule(index) => (
            Source::Rule,
            opened.config.rules.get(index).map(|r| RuleSnapshot {
                index: index + 1,
                condition: r.condition,
                value: r.value.clone(),
            }),
        ),
        Origin::Default => (Source::Default, None),
        Origin::Picker => (Source::Picker, None),
    };
    let mut entry = Entry {
        id: new_id(),
        time: opened.now.rfc3339(),
        url: opened.url.to_owned(),
        source,
        rule,
        browser: opened.destination.browser.clone(),
        profile: opened.destination.profile.clone(),
        profile_name: None,
        result: if opened.error.is_some() { Outcome::Failed } else { Outcome::Launched },
        error: opened.error,
    };
    if let Ok(list) = profiles::of(browsers, &opened.destination.browser)
        && let Ok(directory) = profiles::directory(&opened.destination.profile, &list)
    {
        entry.profile_name = list.iter().find(|p| p.directory == directory).map(|p| p.name.clone());
        entry.profile = directory;
    }
    let result = store.append(&entry);
    result.err().inspect(|e| store.record_write_error(e, opened.now))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(n: usize) -> Entry {
        Entry {
            id: format!("{n:08x}"),
            time: Timestamp(n as i64).rfc3339(),
            url: format!("https://example.com/{n}"),
            source: Source::Default,
            rule: None,
            browser: "b".into(),
            profile: "Default".into(),
            profile_name: None,
            result: Outcome::Launched,
            error: None,
        }
    }

    #[test]
    fn redaction_hides_queries_fragments_and_passwords() {
        assert_eq!(redact("https://u:p@x.com/a?t=1#f"), "https://…@x.com/a?…#…");
        assert_eq!(redact("https://x.com/a?#"), "https://x.com/a?#");
        assert_eq!(redact("https://x.com/a@b"), "https://x.com/a@b");
    }

    #[test]
    fn entries_come_back_newest_first_and_trim_to_the_newest_200() {
        let dir = tempfile::tempdir().unwrap();
        let store = HistoryStore::new(dir.path().join("state/history.jsonl"));
        for n in 0..=TRIM_AT {
            store.append(&entry(n)).unwrap();
        }
        let entries = store.entries().unwrap();
        assert_eq!(entries.len(), KEEP);
        assert_eq!(entries[0], entry(TRIM_AT));
        assert_eq!(fs::read_to_string(&store.path).unwrap().lines().count(), KEEP);
        let mode = |p: &Path| fs::metadata(p).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode(&store.path), 0o600);
        assert_eq!(mode(store.path.parent().unwrap()), 0o700);
    }

    #[test]
    fn a_line_that_does_not_parse_hides_nothing_else() {
        let dir = tempfile::tempdir().unwrap();
        let store = HistoryStore::new(dir.path().join("history.jsonl"));
        store.append(&entry(1)).unwrap();
        fs::OpenOptions::new().append(true).open(&store.path).unwrap().write_all(b"{oops\n").unwrap();
        store.append(&entry(2)).unwrap();
        assert_eq!(store.entries().unwrap(), vec![entry(2), entry(1)]);
    }

    #[test]
    fn clearing_removes_the_file_and_the_last_error() {
        let dir = tempfile::tempdir().unwrap();
        let store = HistoryStore::new(dir.path().join("history.jsonl"));
        store.append(&entry(1)).unwrap();
        store.record_write_error(&io::Error::other("disk full"), Timestamp(0));
        assert!(store.last_write_error().unwrap().contains("disk full"));
        assert_eq!(store.clear().unwrap(), 1);
        assert!(store.entries().unwrap().is_empty());
        assert_eq!(store.last_write_error(), None);
    }
}
