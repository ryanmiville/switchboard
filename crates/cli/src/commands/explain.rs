use serde::Serialize;
use switchboard_core::OpError;
use switchboard_core::history::{Entry, Outcome as Result_, RuleSnapshot, Source};
use switchboard_core::ops::{DestinationInfo, ProfileStatus, RuleRef};

use super::Output;
use crate::cli::Explain;
use crate::format;
use crate::session::Session;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Report {
    url: String,
    matched_rule: Option<RuleRef>,
    destination: DestinationInfo,
    profile_status: ProfileStatus,
    also_matches: Vec<RuleRef>,
    revision: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    history: Option<EntryReport>,
}

/// A history entry as the CLI reports it.
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct EntryReport {
    pub id: String,
    pub time: String,
    pub url: String,
    pub source: Source,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rule: Option<RuleSnapshot>,
    pub browser: String,
    pub browser_name: String,
    pub profile: String,
    pub profile_name: Option<String>,
    pub result: Result_,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl EntryReport {
    pub fn new(entry: &Entry, full_url: bool, session: &Session<'_>) -> EntryReport {
        EntryReport {
            id: entry.id.clone(),
            time: entry.time.clone(),
            url: if full_url { entry.url.clone() } else { entry.redacted_url() },
            source: entry.source,
            rule: entry.rule.clone(),
            browser: entry.browser.clone(),
            browser_name: session.context.browsers.display_name(&entry.browser),
            profile: entry.profile.clone(),
            profile_name: entry.profile_name.clone(),
            result: entry.result,
            error: entry.error.clone(),
        }
    }

    /// "rule 2" or "default" or "picker".
    pub fn how(&self) -> String {
        self.rule.as_ref().map_or_else(
            || match self.source {
                Source::Rule => "rule".into(),
                Source::Default => "default".into(),
                Source::Picker => "picker".into(),
            },
            |r| format!("rule {}", r.index),
        )
    }

    pub fn destination(&self) -> String {
        format!("{} · {}", self.browser_name, self.profile_name.as_deref().unwrap_or(&self.profile))
    }

    pub fn summary(&self) -> String {
        let how = self.rule.as_ref().map_or_else(
            || self.how(),
            |r| format!("rule {} ({} {})", r.index, r.condition.as_str(), r.value),
        );
        let result = match self.result {
            Result_::Failed => format!(", failed: {}", self.error.as_deref().unwrap_or("unknown error")),
            Result_::Launched => ", launched".into(),
        };
        format!("{how} → {}{result}", self.destination())
    }
}

pub fn run(session: &Session<'_>, command: &Explain) -> Result<Output, OpError> {
    let snapshot = session.load()?;
    let linked = session.link(&command.link, &snapshot.config)?;
    let explanation = session.ops(&snapshot).explain(&linked.url);
    let decision = explanation.decision;
    let history = linked.entry.as_ref().map(|e| EntryReport::new(e, command.link.full_urls, session));
    let mut text = if linked.entry.is_some() { format!("URL: {}\n", linked.display) } else { String::new() };
    match &decision.rule {
        Some(rule) => text += &format!("Rule {} matched: {}\n", rule.index, rule.describe()),
        None => text += "No rule matched; using the default destination.\n",
    }
    text += &format!("  → {}\n", decision.destination.label());
    if let Some(problem) = format::problem(decision.profile_status, &decision.destination) {
        text += &format!("  ! {problem}\n");
    }
    if !explanation.also_matches.is_empty() {
        let list: Vec<String> =
            explanation.also_matches.iter().map(|r| format!("rule {} ({})", r.index, r.describe())).collect();
        text += &format!("Also matches, but never reached: {}\n", list.join(", "));
    }
    if let (Some(h), Some(entry)) = (&history, &linked.entry) {
        let age = entry.timestamp().map_or_else(|| h.time.clone(), |t| t.ago(session.context.now));
        text += &format!("At the time ({age}): {}\n", h.summary());
    }
    let report = Report {
        url: linked.display,
        matched_rule: decision.rule,
        destination: decision.destination,
        profile_status: decision.profile_status,
        also_matches: explanation.also_matches,
        revision: snapshot.revision,
        history,
    };
    Ok(Output::new(&report, text))
}
