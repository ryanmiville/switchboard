//! The settings window's model, with no drawing: the config being edited, autosave, and what
//! happens when the file changes underneath (the CLI writes it too).
//!
//! - Edits mark the config dirty; [`Editor::poll`] saves it [`AUTOSAVE_DELAY`] seconds later.
//! - Every save is a compare-and-swap against the revision this editor last loaded or saved.
//! - A file that changed elsewhere reloads silently when there are no pending edits. With pending
//!   edits it is a conflict: the edits stay, and the person chooses to keep them or the saved file.
//! - Saves store every profile as its directory identifier, resolved in its own browser.

use std::collections::BTreeMap;

use switchboard_core::config::{Config, Rule, RuleId};
use switchboard_core::history::HistoryStore;
use switchboard_core::picker::{Favorite, PickerSettings};
use switchboard_core::platform::Family;
use switchboard_core::profiles::{self, Profile};
use switchboard_core::store::{ConfigStore, StoreError};
use switchboard_core::{BrowserInfo, Browsers, Home};

/// Seconds between the last edit and its save.
pub const AUTOSAVE_DELAY: f64 = 0.5;

pub struct Editor {
    pub config: Config,
    pub home: Home,
    pub store: ConfigStore,
    pub history: HistoryStore,
    pub browsers: Box<dyn Browsers>,
    /// Installed browsers, for the browser menus.
    pub installed: Vec<BrowserInfo>,
    /// Each browser the config names, with its profiles or why they couldn't be read.
    pub profiles: BTreeMap<String, Result<Vec<Profile>, String>>,
    /// The file couldn't be read or parsed. Nothing is saved until it is fixed and reloaded.
    pub load_error: Option<String>,
    pub save_error: Option<String>,
    /// A profile no longer resolves, or none is chosen; saving waits until it does.
    pub profile_error: Option<String>,
    /// The file changed elsewhere while edits were pending.
    pub conflict: bool,
    pub history_error: Option<String>,
    revision: Option<String>,
    dirty: bool,
    /// When the pending save is due, in the app clock's seconds; `None` until the next poll
    /// schedules it.
    save_at: Option<f64>,
}

impl Editor {
    /// Loads the config at `store` and lists installed browsers.
    pub fn open(
        home: Home,
        store: ConfigStore,
        history: HistoryStore,
        browsers: Box<dyn Browsers>,
    ) -> Editor {
        let installed = browsers.installed();
        let mut editor = Editor {
            config: Config::default(),
            home,
            store,
            history,
            browsers,
            installed,
            profiles: BTreeMap::new(),
            load_error: None,
            save_error: None,
            profile_error: None,
            conflict: false,
            history_error: None,
            revision: None,
            dirty: false,
            save_at: None,
        };
        editor.reload();
        editor
    }

    pub fn has_unsaved_changes(&self) -> bool {
        self.dirty && self.load_error.is_none()
    }

    /// The first error to show, in the order a person should fix them.
    pub fn error(&self) -> Option<&str> {
        self.load_error.as_deref().or(self.save_error.as_deref()).or(self.profile_error.as_deref())
    }

    /// Changes the config and schedules a save. Refused while the file is unreadable.
    pub fn edit(&mut self, change: impl FnOnce(&mut Config)) {
        if self.load_error.is_some() {
            return;
        }
        let browsers = self.config.browsers();
        change(&mut self.config);
        if self.config.browsers() != browsers {
            self.refresh_profiles();
        }
        self.dirty = true;
        self.save_at = None;
    }

    /// Saves when the autosave delay has passed. Returns true when something visible changed.
    pub fn poll(&mut self, now: f64) -> Option<std::time::Duration> {
        if !self.dirty || self.conflict || self.load_error.is_some() {
            return None;
        }
        let due = *self.save_at.get_or_insert(now + AUTOSAVE_DELAY);
        if now >= due {
            self.flush();
            return None;
        }
        Some(std::time::Duration::from_secs_f64(due - now))
    }

    /// Saves pending edits now: before routing a link, closing the window, or quitting. Returns
    /// whether everything is saved.
    pub fn flush(&mut self) -> bool {
        self.save_at = None;
        if self.load_error.is_some() {
            return false;
        }
        if !self.dirty {
            return true;
        }
        let normalized = match profiles::normalized(&self.config, self.browsers.as_ref()) {
            Ok(config) => config,
            Err(e) => {
                self.profile_error = Some(e.to_string());
                return false;
            }
        };
        match self.store.save(&normalized, self.revision.as_deref()) {
            Ok(revision) => {
                self.revision = Some(revision);
                self.config = normalized;
                self.dirty = false;
                self.save_error = None;
                self.profile_error = None;
                self.conflict = false;
                true
            }
            Err(StoreError::Conflict) => {
                self.conflict = true;
                self.save_error = Some(CONFLICT.into());
                false
            }
            Err(e) => {
                self.save_error = Some(format!("Your changes couldn't be saved. They are still here. {e}"));
                false
            }
        }
    }

    /// Reads the file again, dropping pending edits.
    pub fn reload(&mut self) {
        self.save_at = None;
        match self.store.load() {
            Ok(snapshot) => {
                self.config = snapshot.config;
                self.revision = Some(snapshot.revision);
                self.load_error = None;
                self.save_error = None;
                self.conflict = false;
                self.dirty = false;
                self.refresh_profiles();
            }
            Err(e) => {
                self.revision = match &e {
                    StoreError::Invalid { revision, .. } => Some(revision.clone()),
                    _ => None,
                };
                self.load_error = Some(format!(
                    "Your settings couldn't be read, so nothing will be saved. The file is unchanged: fix it, then reload. {e}"
                ));
                self.dirty = false;
            }
        }
    }

    /// Follows the file when it changed elsewhere. With pending edits, reports a conflict instead.
    /// Returns true when something visible changed.
    pub fn check_external(&mut self) -> bool {
        let Ok(current) = self.store.current_revision() else { return false };
        if Some(&current) == self.revision.as_ref() {
            return false;
        }
        if self.has_unsaved_changes() {
            self.conflict = true;
            self.save_error = Some(CONFLICT.into());
        } else {
            self.reload();
        }
        true
    }

    /// Replaces the file that changed elsewhere with these edits, at the person's request.
    pub fn keep_mine(&mut self) -> bool {
        if self.conflict {
            self.revision = self.store.current_revision().ok();
            self.conflict = false;
        }
        self.flush()
    }

    /// Reads which profiles each named browser has, and whether every saved profile resolves.
    pub fn refresh_profiles(&mut self) {
        self.installed = self.browsers.installed();
        self.profiles = self
            .config
            .browsers()
            .into_iter()
            .map(|b| {
                let found = profiles::of(self.browsers.as_ref(), &b).map_err(|e| e.to_string());
                (b, found)
            })
            .collect();
        self.profile_error =
            profiles::normalized(&self.config, self.browsers.as_ref()).err().map(|e| e.to_string());
    }

    /// The profiles of `browser`, read now if the config doesn't name it yet.
    pub fn profiles_of(&self, browser: &str) -> Vec<Profile> {
        match self.profiles.get(browser) {
            Some(Ok(list)) => list.clone(),
            Some(Err(_)) => Vec::new(),
            None => profiles::of(self.browsers.as_ref(), browser).unwrap_or_default(),
        }
    }

    pub fn browser_name(&self, browser: &str) -> String {
        if browser.is_empty() { "Choose a browser".into() } else { self.browsers.display_name(browser) }
    }

    /// The profile's display name, or what is saved when it doesn't resolve.
    pub fn profile_name(&self, browser: &str, profile: &str) -> String {
        if browser.is_empty() {
            return "Choose a browser first".into();
        }
        let list = self.profiles_of(browser);
        match profiles::directory(profile, &list) {
            Ok(dir) => list.into_iter().find(|p| p.directory == dir).map(|p| p.name).unwrap_or(dir),
            Err(_) if profile.is_empty() => "Choose a profile".into(),
            Err(_) => format!("{profile} (unavailable)"),
        }
    }

    // MARK: Edits

    /// A new default browser. Profiles that inherited the old one were chosen there and can be
    /// different people in the new one, so they need choosing again.
    pub fn select_default_browser(&mut self, browser: &str) {
        if browser == self.config.browser {
            return;
        }
        let browser = browser.to_owned();
        self.edit(|c| {
            c.browser = browser;
            c.default_profile.clear();
            for rule in c.rules.iter_mut().filter(|r| r.browser.is_none()) {
                rule.profile.clear();
            }
        });
    }

    pub fn select_default_profile(&mut self, profile: &str) {
        let profile = profile.to_owned();
        self.edit(|c| c.default_profile = profile);
    }

    pub fn delete_rule(&mut self, id: RuleId) {
        self.edit(|c| c.rules.retain(|r| r.id != id));
    }

    /// Moves a rule up (`-1`) or down (`+1`).
    pub fn move_rule(&mut self, id: RuleId, by: isize) {
        let Some(from) = self.config.index_of(id) else { return };
        let Some(to) = from.checked_add_signed(by).filter(|t| *t < self.config.rules.len()) else { return };
        self.edit(|c| c.rules.swap(from, to));
    }

    /// Moves a rule to position `to` (0-based), as a drag drops it.
    pub fn move_rule_to(&mut self, id: RuleId, to: usize) {
        let Some(from) = self.config.index_of(id) else { return };
        let to = to.min(self.config.rules.len().saturating_sub(1));
        if from == to {
            return;
        }
        self.edit(|c| {
            let rule = c.rules.remove(from);
            c.rules.insert(to, rule);
        });
    }

    /// Adds a new rule or replaces the one with the draft's id.
    pub fn commit_rule(&mut self, rule: Rule) -> bool {
        if self.load_error.is_some() {
            return false;
        }
        match self.config.index_of(rule.id) {
            Some(i) => self.edit(|c| c.rules[i] = rule),
            None => self.edit(|c| c.rules.push(rule)),
        }
        true
    }

    /// The first time the picker is used (no `picker` section yet), starts it with the owner's own
    /// favorites, as the Swift app did. TO REMOVE: these name one person's profiles; a fresh
    /// install should start with none (docs/rewrite/architecture.md, "Decisions").
    pub fn initialize_picker(&mut self) {
        if self.config.picker.is_some() || self.load_error.is_some() {
            return;
        }
        let wanted = [(Family::Helium, "Ryan", "Ryan"), (Family::Chrome, "horizon3.ai", "Horizon 3")];
        let mut settings = PickerSettings::default();
        for (family, profile_name, label) in wanted {
            let Some(browser) = self.installed.iter().find(|b| b.family == family) else { continue };
            let Ok(list) = profiles::read(browser) else { continue };
            let named: Vec<_> = list.iter().filter(|p| p.name == profile_name).collect();
            if let [one] = named.as_slice() {
                settings.favorites.push(Favorite {
                    browser: browser.locator.clone(),
                    profile: one.directory.clone(),
                    name: label.into(),
                });
            }
        }
        self.edit(|c| c.picker = Some(settings));
    }

    pub fn set_history_enabled(&mut self, enabled: bool) {
        // Omitted means enabled, which keeps the file minimal.
        self.edit(|c| {
            c.history = (!enabled).then_some(switchboard_core::config::HistorySettings { enabled: false })
        });
    }

    pub fn clear_history(&mut self) {
        self.history_error = self.history.clear().err().map(|e| format!("History couldn't be cleared. {e}"));
    }
}

const CONFLICT: &str = "The settings file changed outside this window, for example through switchboard-rs, while you had unsaved changes. Your changes are still here: keep them to replace the file, or use the saved settings.";
