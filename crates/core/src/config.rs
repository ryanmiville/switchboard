//! `config.json`: the default destination, the ordered rules, and optional picker and history
//! settings. The CLI and the app share it with no daemon between them; see [`crate::store`].
//!
//! Unknown keys are refused, so a typo in a hand or agent edit is reported instead of ignored.
//! The Swift app's files still load: `routes` is read as `rules`, a rule without `browser`
//! inherits the default browser, and the picker's old Carbon shortcut becomes a shortcut string.

use std::sync::atomic::{AtomicU64, Ordering};

use serde::{Deserialize, Serialize};

use crate::picker::PickerSettings;

/// How a rule's pattern is compared with a link.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Condition {
    /// The pattern appears anywhere in the link, ignoring case.
    Contains,
    /// The pattern is the whole link, ignoring case.
    Exact,
    /// The link's host is the pattern or one of its subdomains.
    Domain,
}

impl Condition {
    pub const ALL: [Condition; 3] = [Condition::Domain, Condition::Contains, Condition::Exact];

    pub fn as_str(self) -> &'static str {
        match self {
            Condition::Contains => "contains",
            Condition::Exact => "exact",
            Condition::Domain => "domain",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Condition::Contains => "Contains",
            Condition::Exact => "Exact",
            Condition::Domain => "Domain",
        }
    }
}

/// A browser and one of its profiles. `browser` is the platform's locator (an app path on macOS,
/// a desktop entry on Linux); `profile` is a Chromium profile directory such as `Profile 1`, or,
/// in old files, a display name.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Destination {
    pub browser: String,
    pub profile: String,
}

/// Identifies a rule while it is in memory, so edits and moves can follow it. Never saved.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct RuleId(u64);

impl Default for RuleId {
    fn default() -> Self {
        static NEXT: AtomicU64 = AtomicU64::new(1);
        RuleId(NEXT.fetch_add(1, Ordering::Relaxed))
    }
}

/// One routing rule. The first rule that matches a link wins.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Rule {
    #[serde(skip)]
    pub id: RuleId,
    pub condition: Condition,
    /// Empty patterns never match.
    pub value: String,
    pub profile: String,
    /// `None` inherits the config's default browser.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub browser: Option<String>,
}

impl Rule {
    pub fn new(condition: Condition, value: impl Into<String>, profile: impl Into<String>) -> Self {
        Rule { id: RuleId::default(), condition, value: value.into(), profile: profile.into(), browser: None }
    }

    pub fn with_browser(mut self, browser: impl Into<String>) -> Self {
        self.browser = Some(browser.into());
        self
    }
}

/// The optional `history` section. Omitted means enabled.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HistorySettings {
    #[serde(default = "enabled")]
    pub enabled: bool,
}

fn enabled() -> bool {
    true
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Config {
    /// The default browser. Empty until one is chosen; links then fail with a recovery action.
    pub browser: String,
    pub default_profile: String,
    #[serde(default, alias = "routes")]
    pub rules: Vec<Rule>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub picker: Option<PickerSettings>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub history: Option<HistorySettings>,
}

impl Default for Config {
    /// What a missing file means: no default browser yet, the `Default` profile, no rules.
    fn default() -> Self {
        Config {
            browser: String::new(),
            default_profile: "Default".into(),
            rules: Vec::new(),
            picker: None,
            history: None,
        }
    }
}

impl Config {
    pub fn parse(bytes: &[u8]) -> Result<Config, serde_json::Error> {
        serde_json::from_slice(bytes)
    }

    /// Pretty JSON with a trailing newline: readable and diffable for people and agents.
    pub fn encode(&self) -> Vec<u8> {
        let mut bytes = serde_json::to_vec_pretty(self).unwrap_or_default();
        bytes.push(b'\n');
        bytes
    }

    pub fn history_enabled(&self) -> bool {
        self.history.as_ref().is_none_or(|h| h.enabled)
    }

    pub fn default_destination(&self) -> Destination {
        Destination { browser: self.browser.clone(), profile: self.default_profile.clone() }
    }

    /// The browser a rule opens: its own, or the default.
    pub fn browser_of<'a>(&'a self, rule: &'a Rule) -> &'a str {
        rule.browser.as_deref().unwrap_or(&self.browser)
    }

    pub fn destination_of(&self, rule: &Rule) -> Destination {
        Destination { browser: self.browser_of(rule).to_owned(), profile: rule.profile.clone() }
    }

    /// Every browser the config names, sorted, without duplicates.
    pub fn browsers(&self) -> Vec<String> {
        let mut all: Vec<String> = std::iter::once(self.browser.clone())
            .chain(self.rules.iter().filter_map(|r| r.browser.clone()))
            .filter(|b| !b.is_empty())
            .collect();
        all.sort();
        all.dedup();
        all
    }

    pub fn index_of(&self, id: RuleId) -> Option<usize> {
        self.rules.iter().position(|r| r.id == id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SWIFT: &str = r#"{
  "browser" : "\/Applications\/Helium.app",
  "defaultProfile" : "Default",
  "history" : { "enabled" : false },
  "picker" : {
    "favorites" : [ { "browser" : "\/Applications\/Helium.app", "name" : "Ryan", "profile" : "Default" } ],
    "shortcut" : { "key" : "Space", "keyCode" : 49, "modifiers" : 6144 }
  },
  "routes" : [
    { "condition" : "domain", "profile" : "Profile 1", "value" : "github.com" },
    { "browser" : "\/Applications\/Google Chrome.app", "condition" : "contains", "profile" : "Work", "value" : "acme" }
  ]
}"#;

    #[test]
    fn a_swift_config_loads_with_its_rules_shortcut_and_settings() {
        let config = Config::parse(SWIFT.as_bytes()).unwrap();
        assert_eq!(config.browser, "/Applications/Helium.app");
        assert_eq!(config.rules.len(), 2);
        assert_eq!(config.rules[0].browser, None);
        assert_eq!(config.browser_of(&config.rules[0]), "/Applications/Helium.app");
        assert_eq!(config.rules[1].profile, "Work");
        assert!(!config.history_enabled());
        assert_eq!(config.picker.unwrap().shortcut.as_str(), "ctrl+alt+space");
    }

    #[test]
    fn a_saved_config_reads_back_the_same_and_omits_what_is_unset() {
        let config = Config::parse(SWIFT.as_bytes()).unwrap();
        let text = String::from_utf8(config.encode()).unwrap();
        assert!(text.contains("\"rules\""), "{text}");
        assert!(!text.contains("routes"));
        assert_eq!(
            text.matches("\"browser\"").count(),
            3,
            "only the overriding rule saves a browser: {text}"
        );
        let again = Config::parse(text.as_bytes()).unwrap();
        assert_eq!(again.encode(), config.encode());
    }

    #[test]
    fn unknown_keys_are_refused_so_typos_surface() {
        let error = Config::parse(br#"{"browser":"b","defaultProfile":"Default","rulez":[]}"#).unwrap_err();
        assert!(error.to_string().contains("rulez"), "{error}");
    }

    #[test]
    fn omitted_history_means_enabled() {
        let config = Config::parse(br#"{"browser":"b","defaultProfile":"Default"}"#).unwrap();
        assert!(config.history_enabled());
        assert!(config.rules.is_empty());
    }
}
