//! Human-readable output. JSON output comes from the report types instead.

use serde::Serialize;
use switchboard_core::Candidate;
use switchboard_core::ops::{DecisionInfo, DestinationInfo, ProfileStatus, RuleInfo, RuleRef};

use crate::commands::HistoryChangeReport;

/// Indented for people at a terminal, one line for programs reading a pipe.
pub fn json(value: &impl Serialize, terminal: bool) -> String {
    let text = if terminal { serde_json::to_string_pretty(value) } else { serde_json::to_string(value) };
    text.unwrap_or_else(|_| r#"{"error":{"code":"failed","message":"Output couldn't be encoded."}}"#.into())
        + "\n"
}

pub fn short(revision: &str) -> &str {
    &revision[..revision.len().min(12)]
}

pub fn via(decision: &DecisionInfo) -> String {
    decision.rule.as_ref().map_or("[default]".into(), |r| format!("[rule {}]", r.index))
}

pub fn decision(decision: &DecisionInfo) -> String {
    format!("{}  {}", decision.destination.label(), via(decision))
}

pub fn rule_line(rule: &RuleInfo) -> String {
    format!("{} {} → {}", rule.condition.as_str(), rule.value, rule.destination.label())
}

/// A warning for a destination whose profile no longer resolves.
pub fn problem(status: ProfileStatus, d: &DestinationInfo) -> Option<String> {
    match status {
        ProfileStatus::Ok => None,
        ProfileStatus::Missing => Some(format!(
            "The profile “{}” doesn't exist in {}. Run `switchboard-rs profiles` to choose another.",
            d.profile, d.browser_name
        )),
        ProfileStatus::Ambiguous => Some(format!(
            "Several profiles in {} are named “{}”. Choose one by its directory.",
            d.browser_name, d.profile
        )),
        ProfileStatus::Unavailable if d.browser.is_empty() => {
            Some("No default browser is chosen. Run `switchboard-rs default --browser <browser> --profile <profile>`.".into())
        }
        ProfileStatus::Unavailable => {
            Some(format!("{} isn't installed at {}, or its profiles couldn't be read.", d.browser_name, d.browser))
        }
    }
}

pub fn candidate(c: &Candidate) -> String {
    let line = if let Some(index) = c.index {
        match (&c.condition, &c.value) {
            (Some(condition), Some(value)) => format!("rule {index}: {} {value}", condition.as_str()),
            _ => format!("rule {index}"),
        }
    } else if let Some(id) = &c.id {
        [Some(id.as_str()), c.url.as_deref()].into_iter().flatten().collect::<Vec<_>>().join("  ")
    } else if let Some(profile) = &c.profile {
        format!(
            "{} · {} ({profile})",
            c.browser_name.as_deref().or(c.browser.as_deref()).unwrap_or_default(),
            c.profile_name.as_deref().unwrap_or(profile)
        )
    } else if let Some(browser) = &c.browser {
        let id = c.browser_id.as_ref().map(|i| format!("  ({i})")).unwrap_or_default();
        format!("{}  {browser}{id}", c.browser_name.as_deref().unwrap_or(browser))
    } else {
        c.agent.clone().unwrap_or_default()
    };
    let mut text = format!("  - {line}\n");
    if let Some(suggestion) = &c.suggestion {
        text += &format!("    {suggestion}\n");
    }
    text
}

pub fn padded(value: &str, width: usize) -> String {
    format!("{value:<width$}")
}

pub fn written(dry_run: bool, revision: &str) -> String {
    if dry_run {
        "No changes written (dry run).\n".into()
    } else {
        format!("Saved. Revision {}.\n", short(revision))
    }
}

pub fn history_changes(changes: &[HistoryChangeReport], checked: bool) -> String {
    if !checked {
        return String::new();
    }
    if changes.is_empty() {
        return "No recent links would open somewhere else.\n".into();
    }
    let mut text = "Recent links that would now open somewhere else:\n".to_owned();
    for c in changes {
        text += &format!("  {}  {}\n    {}  →  {}\n", c.id, c.url, decision(&c.before), decision(&c.after));
    }
    text
}

pub fn unreachable(rules: &[RuleRef]) -> String {
    rules.iter().map(|r| format!("  ! Rule {} ({}) can no longer match.\n", r.index, r.describe())).collect()
}
