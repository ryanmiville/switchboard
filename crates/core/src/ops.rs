//! Reading and changing rules, shared by every CLI command (and usable by the app). Validation
//! matches the editor: profiles resolve within their destination's browser, directory identifiers
//! win over display names, and ambiguous names are refused. Edits change only what they name.

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

use serde::Serialize;

use crate::config::{Condition, Config, Destination, Rule};
use crate::error::{Candidate, Code, OpError};
use crate::history::Entry;
use crate::home::Home;
use crate::platform::{BrowserInfo, Browsers};
use crate::profiles::{self, Profile, ProfileError};
use crate::router;
use crate::shadowing::{self, Unreachable};
use crate::url;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ProfileStatus {
    Ok,
    Missing,
    Ambiguous,
    /// The browser isn't installed, or its profiles couldn't be read.
    Unavailable,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DestinationInfo {
    pub browser: String,
    pub browser_name: String,
    /// The directory identifier when the saved profile resolves, otherwise the saved value.
    pub profile: String,
    pub profile_name: Option<String>,
}

impl DestinationInfo {
    /// `Google Chrome · Work (Profile 2)`.
    pub fn label(&self) -> String {
        match &self.profile_name {
            Some(name) => format!("{} · {name} ({})", self.browser_name, self.profile),
            None => format!("{} · {}", self.browser_name, self.profile),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct RuleRef {
    /// 1-based.
    pub index: usize,
    pub condition: Condition,
    pub value: String,
}

impl RuleRef {
    pub fn describe(&self) -> String {
        format!("{} {}", self.condition.as_str(), self.value)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuleInfo {
    pub index: usize,
    pub condition: Condition,
    pub value: String,
    /// `None` when the rule inherits the default browser.
    pub browser: Option<String>,
    pub profile: String,
    pub destination: DestinationInfo,
    pub profile_status: ProfileStatus,
    /// The earlier rule (1-based) that always matches first, if this rule can never match.
    pub shadowed_by: Option<usize>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DecisionInfo {
    pub rule: Option<RuleRef>,
    pub destination: DestinationInfo,
    pub profile_status: ProfileStatus,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Explanation {
    pub decision: DecisionInfo,
    /// Later rules that also match but are never reached.
    pub also_matches: Vec<RuleRef>,
}

#[derive(Clone, Debug)]
pub struct HistoryChange {
    pub entry: Entry,
    pub before: DecisionInfo,
    pub after: DecisionInfo,
}

#[derive(Clone, Debug)]
pub struct RouteRequest {
    pub url: String,
    pub profile: String,
    pub browser: Option<String>,
    pub condition: Condition,
    pub value: Option<String>,
    pub allow_shadowing: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BrowserChoice {
    Default,
    Browser(String),
}

#[derive(Clone, Debug, Default)]
pub struct RuleUpdate {
    pub profile: Option<String>,
    pub browser: Option<BrowserChoice>,
    pub condition: Option<Condition>,
    pub value: Option<String>,
    pub allow_shadowing: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Action {
    Added,
    Updated,
    Moved,
    Removed,
    Unchanged,
}

#[derive(Clone, Debug)]
pub struct RuleChange {
    pub config: Config,
    pub action: Action,
    /// 0-based position of the affected rule in `config`, or in the original for a removal.
    pub index: Option<usize>,
    /// Rules that can no longer match because of this change.
    pub unreachable: Vec<Unreachable>,
}

impl RuleChange {
    pub fn changed(&self) -> bool {
        self.action != Action::Unchanged
    }
}

#[derive(Clone, Debug)]
pub struct DefaultChange {
    pub config: Config,
    pub changed: bool,
}

type Cache = Rc<RefCell<HashMap<String, Result<Vec<Profile>, ProfileError>>>>;

/// Rule operations on one config. Profile lists are read once per browser.
pub struct Ops<'a> {
    pub config: Config,
    pub browsers: &'a dyn Browsers,
    pub home: &'a Home,
    cache: Cache,
}

impl<'a> Ops<'a> {
    pub fn new(config: Config, browsers: &'a dyn Browsers, home: &'a Home) -> Self {
        Ops { config, browsers, home, cache: Cache::default() }
    }

    /// The same lookups on an edited config, sharing the profile cache.
    pub fn with(&self, config: Config) -> Ops<'a> {
        Ops { config, browsers: self.browsers, home: self.home, cache: self.cache.clone() }
    }

    // MARK: Profiles

    pub fn profiles(&self, browser: &str) -> Result<Vec<Profile>, ProfileError> {
        if let Some(found) = self.cache.borrow().get(browser) {
            return found.clone();
        }
        let found = profiles::of(self.browsers, browser);
        self.cache.borrow_mut().insert(browser.to_owned(), found.clone());
        found
    }

    /// How a saved profile resolves: a directory, then an unambiguous legacy display name.
    pub fn resolve_saved(&self, profile: &str, browser: &str) -> (Option<String>, ProfileStatus) {
        let Ok(available) = self.profiles(browser) else { return (None, ProfileStatus::Unavailable) };
        match profiles::directory(profile, &available) {
            Ok(directory) => (Some(directory), ProfileStatus::Ok),
            Err(ProfileError::Ambiguous(_)) => (None, ProfileStatus::Ambiguous),
            Err(_) => (None, ProfileStatus::Missing),
        }
    }

    pub fn describe(&self, destination: &Destination) -> (DestinationInfo, ProfileStatus) {
        let (directory, status) = self.resolve_saved(&destination.profile, &destination.browser);
        let name = directory.as_ref().and_then(|d| {
            self.profiles(&destination.browser).ok()?.into_iter().find(|p| &p.directory == d).map(|p| p.name)
        });
        let info = DestinationInfo {
            browser: destination.browser.clone(),
            browser_name: self.browser_name(&destination.browser),
            profile: directory.unwrap_or_else(|| destination.profile.clone()),
            profile_name: name,
        };
        (info, status)
    }

    pub fn browser_name(&self, browser: &str) -> String {
        if browser.is_empty() { "No browser".into() } else { self.browsers.display_name(browser) }
    }

    /// Destinations compare by standardized browser and resolved profile directory.
    pub fn key(&self, destination: &Destination) -> Destination {
        Destination {
            browser: self.browsers.standardize(&destination.browser),
            profile: self
                .resolve_saved(&destination.profile, &destination.browser)
                .0
                .unwrap_or_else(|| destination.profile.clone()),
        }
    }

    // MARK: Reading

    pub fn rules(&self) -> Vec<RuleInfo> {
        let mut shadowed: HashMap<usize, usize> = HashMap::new();
        for u in shadowing::unreachable(&self.config.rules) {
            shadowed.entry(u.rule).or_insert(u.by);
        }
        self.config
            .rules
            .iter()
            .enumerate()
            .map(|(i, rule)| {
                let (destination, profile_status) = self.describe(&self.config.destination_of(rule));
                RuleInfo {
                    index: i + 1,
                    condition: rule.condition,
                    value: rule.value.clone(),
                    browser: rule.browser.clone(),
                    profile: rule.profile.clone(),
                    destination,
                    profile_status,
                    shadowed_by: shadowed.get(&i).map(|b| b + 1),
                }
            })
            .collect()
    }

    pub fn reference(&self, index: usize) -> RuleRef {
        let rule = &self.config.rules[index];
        RuleRef { index: index + 1, condition: rule.condition, value: rule.value.clone() }
    }

    pub fn decision(&self, link: &str) -> DecisionInfo {
        let decision = router::decide(&self.config, link);
        let (destination, profile_status) = self.describe(&decision.destination);
        DecisionInfo { rule: decision.rule.map(|i| self.reference(i)), destination, profile_status }
    }

    pub fn explain(&self, link: &str) -> Explanation {
        let matched = router::decide(&self.config, link).rule;
        let also_matches = match matched {
            Some(m) => (m + 1..self.config.rules.len())
                .filter(|&i| router::matches(&self.config.rules[i], link))
                .map(|i| self.reference(i))
                .collect(),
            None => Vec::new(),
        };
        Explanation { decision: self.decision(link), also_matches }
    }

    /// Links from history that would open somewhere else with `edited`. Each link is checked once.
    pub fn history_changes(&self, edited: &Config, entries: &[Entry]) -> Vec<HistoryChange> {
        let after = self.with(edited.clone());
        let mut seen = HashSet::new();
        entries
            .iter()
            .filter(|e| seen.insert(e.url.clone()))
            .filter_map(|entry| {
                let old = router::decide(&self.config, &entry.url).destination;
                let new = router::decide(edited, &entry.url).destination;
                (self.key(&old) != self.key(&new)).then(|| HistoryChange {
                    entry: entry.clone(),
                    before: self.decision(&entry.url),
                    after: after.decision(&entry.url),
                })
            })
            .collect()
    }

    // MARK: Resolving names

    pub fn known_browsers(&self) -> Vec<BrowserInfo> {
        self.browsers.known(&self.config.browsers())
    }

    pub fn browser_candidate(info: &BrowserInfo) -> Candidate {
        Candidate {
            browser: Some(info.locator.clone()),
            browser_name: Some(info.name.clone()),
            browser_id: Some(info.id.clone()),
            ..Candidate::default()
        }
    }

    /// A path, then an id (bundle identifier or desktop entry), then a name or alias, ignoring case.
    pub fn resolve_browser(&self, query: &str) -> Result<BrowserInfo, OpError> {
        let query = query.trim();
        let known = self.known_browsers();
        let candidates = || known.iter().map(Self::browser_candidate).collect();
        if query.contains('/') || query.starts_with('~') {
            let path = self.home.expand(query);
            return self.browsers.at(&path.to_string_lossy()).ok_or_else(|| {
                OpError::new(
                    Code::BrowserNotFound,
                    format!(
                        "“{query}” isn't a supported Chromium browser. Choose one of the installed browsers."
                    ),
                )
                .with(candidates())
            });
        }
        let by_id: Vec<_> = known.iter().filter(|b| b.id.eq_ignore_ascii_case(query)).collect();
        if let [one] = by_id.as_slice() {
            return Ok((*one).clone());
        }
        let name = strip_suffix_ignore_case(query, ".app");
        let found: Vec<_> =
            if by_id.is_empty() { known.iter().filter(|b| b.answers_to(name)).collect() } else { by_id };
        match found.as_slice() {
            [one] => Ok((*one).clone()),
            [] => Err(OpError::new(
                Code::BrowserNotFound,
                format!("No installed browser matches “{query}”. Use a name, id, or path."),
            )
            .with(candidates())),
            many => Err(OpError::new(
                Code::AmbiguousBrowser,
                format!("“{query}” matches {} browsers. Use its path.", many.len()),
            )
            .with(many.iter().map(|b| Self::browser_candidate(b)).collect())),
        }
    }

    /// A directory identifier, then a display name, then either ignoring case; only when one
    /// profile matches.
    pub fn resolve_profile(&self, query: &str, browser: &str) -> Result<Profile, OpError> {
        let browser_name = self.browser_name(browser);
        let available = self.profiles(browser).map_err(|e| match e {
            ProfileError::BrowserUnavailable(_) => OpError::new(
                Code::BrowserNotFound,
                format!("{browser_name} isn't installed at {browser}, so its profiles can't be listed."),
            )
            .with(self.known_browsers().iter().map(Self::browser_candidate).collect()),
            other => OpError::new(
                Code::ProfilesUnreadable,
                format!("{browser_name}'s profiles couldn't be read. {other}"),
            ),
        })?;
        if let Some(p) = available.iter().find(|p| p.directory == query) {
            return Ok(p.clone());
        }
        let named: Vec<_> = available.iter().filter(|p| p.name == query).collect();
        let found: Vec<_> = if named.is_empty() {
            available
                .iter()
                .filter(|p| p.name.eq_ignore_ascii_case(query) || p.directory.eq_ignore_ascii_case(query))
                .collect()
        } else {
            named
        };
        if let [one] = found.as_slice() {
            return Ok((*one).clone());
        }
        let candidates = if found.is_empty() { available.iter().collect() } else { found.clone() }
            .into_iter()
            .map(|p| Candidate {
                browser: Some(browser.to_owned()),
                browser_name: Some(browser_name.clone()),
                profile: Some(p.directory.clone()),
                profile_name: Some(p.name.clone()),
                ..Candidate::default()
            })
            .collect();
        if found.is_empty() {
            Err(OpError::new(Code::ProfileNotFound, format!("No profile “{query}” in {browser_name}."))
                .with(candidates))
        } else {
            Err(OpError::new(
                Code::AmbiguousProfile,
                format!("“{query}” matches {} profiles in {browser_name}.", found.len()),
            )
            .with(candidates))
        }
    }

    pub fn rule_candidates(&self) -> Vec<Candidate> {
        self.config.rules.iter().enumerate().map(|(i, r)| rule_candidate(i, r)).collect()
    }

    /// The 0-based index of 1-based `position`.
    pub fn rule_index(&self, position: usize) -> Result<usize, OpError> {
        let count = self.config.rules.len();
        if position == 0 || position > count {
            let message = if count == 0 {
                "There are no rules.".to_owned()
            } else {
                format!("There is no rule {position}. Rules are numbered 1–{count}.")
            };
            return Err(OpError::new(Code::RuleNotFound, message).with(self.rule_candidates()));
        }
        Ok(position - 1)
    }

    // MARK: Changing rules

    /// Makes `request.url` open at the requested destination: updates a rule with the same
    /// condition and pattern, or inserts one just before the rule that matches now (so only links
    /// that matched it can change), or appends one.
    pub fn route(&self, request: &RouteRequest) -> Result<RuleChange, OpError> {
        let value = rule_value(request)?;
        let (override_browser, target) = self.target(request.browser.as_deref(), &request.profile)?;
        let current = router::decide(&self.config, &request.url);
        if self.key(&current.destination) == self.key(&target) {
            return Ok(RuleChange {
                config: self.config.clone(),
                action: Action::Unchanged,
                index: current.rule,
                unreachable: vec![],
            });
        }
        let mut edited = self.config.clone();
        let existing =
            self.config.rules.iter().position(|r| {
                r.condition == request.condition && r.value.to_lowercase() == value.to_lowercase()
            });
        let (index, action) = match existing {
            Some(i) => {
                edited.rules[i].browser = override_browser;
                edited.rules[i].profile = target.profile.clone();
                (i, Action::Updated)
            }
            None => {
                let i = current.rule.unwrap_or(self.config.rules.len());
                let mut rule = Rule::new(request.condition, value, target.profile.clone());
                rule.browser = override_browser;
                edited.rules.insert(i, rule);
                (i, Action::Added)
            }
        };
        // Verify first: a rule that doesn't route the link as asked matters more than what it hides.
        let after = router::decide(&edited, &request.url);
        if self.key(&after.destination) != self.key(&target) {
            let reached = self.with(edited.clone()).decision(&request.url);
            let via = reached
                .rule
                .as_ref()
                .map_or("the default".to_owned(), |r| format!("rule {} ({})", r.index, r.describe()));
            return Err(OpError::new(
                Code::VerificationFailed,
                format!(
                    "After the change the link would still open in {} through {via}. Nothing was written.",
                    reached.destination.label()
                ),
            ));
        }
        let unreachable = self.check_shadowing(&edited, index, request.allow_shadowing)?;
        Ok(RuleChange { config: edited, action, index: Some(index), unreachable })
    }

    pub fn update_rule(&self, position: usize, update: &RuleUpdate) -> Result<RuleChange, OpError> {
        let index = self.rule_index(position)?;
        if update.profile.is_none()
            && update.browser.is_none()
            && update.condition.is_none()
            && update.value.is_none()
        {
            return Err(OpError::invalid(
                "Pass at least one of --profile, --browser, --default-browser, --match, or --value.",
            ));
        }
        if update.browser.is_some() && update.profile.is_none() {
            return Err(OpError::invalid(
                "Changing a rule's browser needs --profile: profile identifiers belong to one browser.",
            ));
        }
        let mut rule = self.config.rules[index].clone();
        match &update.browser {
            Some(BrowserChoice::Browser(query)) => rule.browser = Some(self.resolve_browser(query)?.locator),
            Some(BrowserChoice::Default) => rule.browser = None,
            None => {}
        }
        if let Some(profile) = &update.profile {
            let browser = self.config.browser_of(&rule).to_owned();
            rule.profile = self.resolve_profile(profile, &browser)?.directory;
        }
        if let Some(condition) = update.condition {
            rule.condition = condition;
        }
        if let Some(value) = &update.value {
            rule.value = pattern(value)?;
        }
        if rule.condition == Condition::Domain && (update.condition.is_some() || update.value.is_some()) {
            validate_domain(&rule.value)?;
        }
        let mut edited = self.config.clone();
        edited.rules[index] = rule;
        if edited == self.config {
            return Ok(RuleChange {
                config: edited,
                action: Action::Unchanged,
                index: Some(index),
                unreachable: vec![],
            });
        }
        let unreachable = self.check_shadowing(&edited, index, update.allow_shadowing)?;
        Ok(RuleChange { config: edited, action: Action::Updated, index: Some(index), unreachable })
    }

    pub fn move_rule(&self, from: usize, to: usize) -> Result<RuleChange, OpError> {
        let source = self.rule_index(from)?;
        let destination = self.rule_index(to)?;
        if source == destination {
            return Ok(RuleChange {
                config: self.config.clone(),
                action: Action::Unchanged,
                index: Some(source),
                unreachable: vec![],
            });
        }
        let mut edited = self.config.clone();
        let rule = edited.rules.remove(source);
        edited.rules.insert(destination, rule);
        let unreachable = shadowing::newly_unreachable(&self.config.rules, &edited.rules);
        Ok(RuleChange { config: edited, action: Action::Moved, index: Some(destination), unreachable })
    }

    pub fn remove_rule(&self, position: usize) -> Result<RuleChange, OpError> {
        let index = self.rule_index(position)?;
        let mut edited = self.config.clone();
        edited.rules.remove(index);
        Ok(RuleChange { config: edited, action: Action::Removed, index: Some(index), unreachable: vec![] })
    }

    /// Changes the default destination. Rules that inherit the default browser chose their profile
    /// in it, and the same directory can be a different person in another browser, so changing the
    /// default browser is refused while any rule inherits it. Nothing is cleared silently.
    pub fn set_default(
        &self,
        browser: Option<&str>,
        profile: Option<&str>,
    ) -> Result<DefaultChange, OpError> {
        let mut edited = self.config.clone();
        if let Some(query) = browser {
            let info = self.resolve_browser(query)?;
            if info.locator != self.browsers.standardize(&self.config.browser) {
                if profile.is_none() {
                    return Err(OpError::invalid(
                        "Changing the default browser needs --profile: profile identifiers belong to one browser.",
                    ));
                }
                let inheriting: Vec<usize> = (0..self.config.rules.len())
                    .filter(|&i| self.config.rules[i].browser.is_none())
                    .collect();
                if !inheriting.is_empty() && !self.config.browser.is_empty() {
                    let one = inheriting.len() == 1;
                    let numbers: Vec<String> = inheriting.iter().map(|i| (i + 1).to_string()).collect();
                    let message = format!(
                        "{} {} {} the default browser. Give {} an explicit browser and profile with `rules update` first.",
                        if one { "Rule" } else { "Rules" },
                        list(&numbers),
                        if one { "uses" } else { "use" },
                        if one { "it" } else { "each one" },
                    );
                    let candidates = inheriting
                        .iter()
                        .map(|&i| {
                            let rule = &self.config.rules[i];
                            let directory = self
                                .resolve_saved(&rule.profile, &self.config.browser)
                                .0
                                .unwrap_or_else(|| rule.profile.clone());
                            Candidate {
                                browser: Some(self.config.browser.clone()),
                                profile: Some(directory.clone()),
                                suggestion: Some(format!(
                                    "{} rules update {} --browser {} --profile {}",
                                    crate::identity::CLI_NAME,
                                    i + 1,
                                    quoted(&self.config.browser),
                                    quoted(&directory)
                                )),
                                ..rule_candidate(i, rule)
                            }
                        })
                        .collect();
                    return Err(OpError::new(Code::InheritingRules, message).with(candidates));
                }
                edited.browser = info.locator;
            }
        }
        if let Some(profile) = profile {
            edited.default_profile = self.resolve_profile(profile, &edited.browser)?.directory;
        }
        let changed = edited != self.config;
        Ok(DefaultChange { config: edited, changed })
    }

    /// Without a browser, the rule inherits the default browser and the profile resolves there.
    fn target(&self, browser: Option<&str>, profile: &str) -> Result<(Option<String>, Destination), OpError> {
        match browser {
            None => {
                let directory = self.resolve_profile(profile, &self.config.browser)?.directory;
                Ok((None, Destination { browser: self.config.browser.clone(), profile: directory }))
            }
            Some(query) => {
                let info = self.resolve_browser(query)?;
                let directory = self.resolve_profile(profile, &info.locator)?.directory;
                Ok((Some(info.locator.clone()), Destination { browser: info.locator, profile: directory }))
            }
        }
    }

    /// The changed rule must stay reachable; rules it would hide need permission.
    fn check_shadowing(
        &self,
        edited: &Config,
        index: usize,
        allowed: bool,
    ) -> Result<Vec<Unreachable>, OpError> {
        let unreachable = shadowing::newly_unreachable(&self.config.rules, &edited.rules);
        let after = self.with(edited.clone());
        if let Some(own) = unreachable.iter().find(|u| u.rule == index) {
            return Err(OpError::new(
                Code::VerificationFailed,
                format!(
                    "Rule {} would never match: rule {} ({}) always matches first. Nothing was written.",
                    index + 1,
                    own.by + 1,
                    after.reference(own.by).describe()
                ),
            )
            .with(vec![rule_candidate(own.by, &edited.rules[own.by])]));
        }
        if !allowed && !unreachable.is_empty() {
            let hidden: Vec<String> = unreachable
                .iter()
                .map(|u| format!("rule {} ({})", u.rule + 1, after.reference(u.rule).describe()))
                .collect();
            return Err(OpError::new(
                Code::WouldShadow,
                format!(
                    "Rule {} ({}) would stop {} from ever matching. Use a narrower --value, or pass --allow-shadowing.",
                    index + 1,
                    after.reference(index).describe(),
                    list(&hidden)
                ),
            )
            .with(unreachable.iter().map(|u| rule_candidate(u.rule, &edited.rules[u.rule])).collect()));
        }
        Ok(unreachable)
    }
}

fn rule_candidate(index: usize, rule: &Rule) -> Candidate {
    Candidate {
        index: Some(index + 1),
        condition: Some(rule.condition),
        value: Some(rule.value.clone()),
        ..Candidate::default()
    }
}

fn rule_value(request: &RouteRequest) -> Result<String, OpError> {
    if let Some(value) = &request.value {
        let value = pattern(value)?;
        if request.condition == Condition::Domain {
            validate_domain(&value)?;
        }
        return Ok(value);
    }
    match request.condition {
        Condition::Domain => url::web_host(&request.url).ok_or_else(|| {
            OpError::invalid(
                "Domain rules only match web links. Use --match exact, or --match contains with --value.",
            )
        }),
        Condition::Exact => Ok(request.url.clone()),
        Condition::Contains => {
            Err(OpError::invalid("--match contains needs --value, the text the link must contain."))
        }
    }
}

/// A trimmed, non-empty pattern.
pub fn pattern(value: &str) -> Result<String, OpError> {
    let value = value.trim();
    if value.is_empty() {
        return Err(OpError::invalid("--value can't be empty: empty patterns never match."));
    }
    Ok(value.to_owned())
}

pub fn validate_domain(value: &str) -> Result<(), OpError> {
    if value.contains('/') || value.chars().any(char::is_whitespace) {
        return Err(OpError::invalid(format!(
            "“{value}” isn't a domain. Domain rules take a host such as github.com, which also matches its subdomains."
        )));
    }
    Ok(())
}

/// "a", "a and b", "a, b, and c".
pub fn list(items: &[String]) -> String {
    match items {
        [] => String::new(),
        [one] => one.clone(),
        [a, b] => format!("{a} and {b}"),
        [rest @ .., last] => format!("{}, and {last}", rest.join(", ")),
    }
}

/// Quotes `value` for a POSIX shell when it needs it.
pub fn quoted(value: &str) -> String {
    if !value.is_empty() && value.chars().all(|c| c.is_alphanumeric() || "/._-".contains(c)) {
        value.to_owned()
    } else {
        format!("'{}'", value.replace('\'', "'\\''"))
    }
}

fn strip_suffix_ignore_case<'s>(text: &'s str, suffix: &str) -> &'s str {
    let cut = text.len().saturating_sub(suffix.len());
    if text.is_char_boundary(cut) && text[cut..].eq_ignore_ascii_case(suffix) { &text[..cut] } else { text }
}
