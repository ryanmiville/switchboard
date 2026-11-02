//! Per-run state: where the files are, loading and committing the config, and resolving history
//! entries. Wraps core's errors in the CLI's codes.

use std::path::PathBuf;

use switchboard_core::history::{Entry, HistoryStore};
use switchboard_core::ops::Ops;
use switchboard_core::store::{ConfigStore, Snapshot};
use switchboard_core::time::Timestamp;
use switchboard_core::{Browsers, Candidate, Code, Config, Env, Home, OpError, url};

use crate::cli::{Change, Global, Link};
use crate::format;

/// Everything a command reads from outside, so tests can run the binary against a temporary home.
pub struct Context<'a> {
    pub home: Home,
    pub env: Env,
    pub now: Timestamp,
    pub browsers: &'a dyn Browsers,
    /// Whether stdout is a terminal: JSON is indented for people, one line for programs.
    pub terminal: bool,
}

pub struct Session<'a> {
    pub context: &'a Context<'a>,
    pub config_path: PathBuf,
    pub history_path: PathBuf,
}

/// A link to explain or route: typed, or from history.
pub struct Linked {
    pub url: String,
    pub entry: Option<Entry>,
    /// What to show: history URLs are redacted unless --full-urls.
    pub display: String,
}

impl<'a> Session<'a> {
    pub fn new(context: &'a Context<'a>, global: &Global) -> Self {
        let pick = |flag: &Option<String>, var: &str, default: PathBuf| {
            flag.as_deref().or(context.env.var(var)).map_or(default, |p| context.home.expand(p))
        };
        Session {
            config_path: pick(&global.config, "SWITCHBOARD_RS_CONFIG", context.home.config_file()),
            history_path: pick(&global.history_file, "SWITCHBOARD_RS_HISTORY", context.home.history_file()),
            context,
        }
    }

    pub fn store(&self) -> ConfigStore {
        ConfigStore::new(&self.config_path)
    }

    pub fn history(&self) -> HistoryStore {
        HistoryStore::new(&self.history_path)
    }

    pub fn load(&self) -> Result<Snapshot, OpError> {
        Ok(self.store().load()?)
    }

    pub fn ops(&self, snapshot: &Snapshot) -> Ops<'a> {
        Ops::new(snapshot.config.clone(), self.context.browsers, &self.context.home)
    }

    /// Refuses with `conflict` when --if-revision doesn't match the loaded file.
    pub fn check(&self, snapshot: &Snapshot, change: &Change) -> Result<(), OpError> {
        let Some(expected) = change.if_revision.as_deref().map(str::to_lowercase) else { return Ok(()) };
        if expected.len() < 8 {
            return Err(OpError::invalid("Pass the full revision from --json output to --if-revision."));
        }
        if !snapshot.revision.starts_with(&expected) {
            return Err(OpError::new(
                Code::Conflict,
                format!(
                    "The configuration changed since revision {}; it is now {}. Nothing was written. Look again, then retry.",
                    format::short(&expected),
                    format::short(&snapshot.revision)
                ),
            ));
        }
        Ok(())
    }

    /// Saves `config` over the loaded file unless this is a dry run or nothing changed, and
    /// returns the file's revision afterward.
    pub fn commit(&self, config: &Config, snapshot: &Snapshot, change: &Change) -> Result<String, OpError> {
        if change.dry_run || *config == snapshot.config {
            return Ok(snapshot.revision.clone());
        }
        Ok(self.store().save(config, Some(&snapshot.revision))?)
    }

    pub fn history_entries(&self, config: &Config) -> Result<Vec<Entry>, OpError> {
        if !config.history_enabled() {
            return Err(OpError::new(
                Code::HistoryDisabled,
                "History is turned off (`history on`, or Settings → General). Pass the URL instead.",
            ));
        }
        self.history().entries().map_err(|e| {
            OpError::new(Code::HistoryUnreadable, format!("The history file couldn't be read. {e}"))
        })
    }

    /// History that is off or unreadable only means there is nothing to compare against.
    pub fn recent_history(&self, config: &Config) -> Option<Vec<Entry>> {
        self.history_entries(config).ok()
    }

    pub fn history_entry(&self, id: Option<&str>, config: &Config) -> Result<Entry, OpError> {
        let entries = self.history_entries(config)?;
        let Some(id) = id.map(str::to_lowercase) else {
            return entries.into_iter().next().ok_or_else(|| {
                OpError::new(Code::HistoryEntryNotFound, "History is empty. Pass the URL instead.")
            });
        };
        if let Some(exact) = entries.iter().find(|e| e.id == id) {
            return Ok(exact.clone());
        }
        if id.len() < 4 {
            return Err(OpError::invalid("History IDs need at least four characters."));
        }
        let found: Vec<&Entry> =
            entries.iter().filter(|e| e.id.starts_with(&id) || e.id.ends_with(&id)).collect();
        if let [one] = found.as_slice() {
            return Ok((*one).clone());
        }
        let candidates = if found.is_empty() { entries.iter().take(10).collect() } else { found.clone() }
            .into_iter()
            .map(|e| Candidate {
                id: Some(e.id.clone()),
                time: Some(e.time.clone()),
                url: Some(e.redacted_url()),
                ..Candidate::default()
            })
            .collect();
        if found.is_empty() {
            Err(OpError::new(Code::HistoryEntryNotFound, format!("No history entry matches “{id}”."))
                .with(candidates))
        } else {
            Err(OpError::new(
                Code::AmbiguousHistoryEntry,
                format!("“{id}” matches {} history entries.", found.len()),
            )
            .with(candidates))
        }
    }

    pub fn link(&self, link: &Link, config: &Config) -> Result<Linked, OpError> {
        if let Some(value) = &link.target.url {
            if !(url::is_web(value) || url::is_local_file(value)) {
                return Err(OpError::invalid(format!(
                    "“{value}” isn't a complete URL. Pass one such as https://example.com/page."
                )));
            }
            return Ok(Linked { url: value.clone(), entry: None, display: value.clone() });
        }
        let entry = self.history_entry(link.target.history.as_deref(), config)?;
        let display = if link.full_urls { entry.url.clone() } else { entry.redacted_url() };
        Ok(Linked { url: entry.url.clone(), display, entry: Some(entry) })
    }
}
