use serde::Serialize;
use switchboard_core::ops::ProfileStatus;
use switchboard_core::{Condition, OpError, profiles};

use super::{DefaultInfo, Output};
use crate::format;
use crate::session::Session;

#[derive(Serialize, Default)]
#[serde(rename_all = "camelCase")]
struct Report {
    ok: bool,
    config: ConfigCheck,
    #[serde(skip_serializing_if = "Option::is_none")]
    default: Option<DefaultInfo>,
    browsers: Vec<BrowserCheck>,
    rules: Vec<RuleProblem>,
    history: HistoryCheck,
    version: String,
}

#[derive(Serialize, Default)]
struct ConfigCheck {
    path: String,
    exists: bool,
    valid: bool,
    revision: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct BrowserCheck {
    path: String,
    name: String,
    installed: bool,
    local_state: Option<String>,
    profile_count: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Serialize)]
struct RuleProblem {
    index: usize,
    condition: Condition,
    value: String,
    /// empty_pattern, profile_missing, profile_ambiguous, profile_unavailable, or unreachable.
    problem: String,
    message: String,
}

#[derive(Serialize, Default)]
#[serde(rename_all = "camelCase")]
struct HistoryCheck {
    path: String,
    enabled: bool,
    entries: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
    last_write_error: Option<String>,
}

pub fn run(session: &Session<'_>) -> Result<Output, OpError> {
    let store = session.store();
    let mut report = Report {
        config: ConfigCheck {
            path: session.config_path.to_string_lossy().into_owned(),
            exists: session.config_path.exists(),
            ..ConfigCheck::default()
        },
        history: HistoryCheck {
            path: session.history_path.to_string_lossy().into_owned(),
            enabled: true,
            ..HistoryCheck::default()
        },
        version: env!("CARGO_PKG_VERSION").to_owned(),
        ..Report::default()
    };
    match store.load() {
        Ok(snapshot) => {
            report.config.valid = true;
            report.config.revision = Some(snapshot.revision.clone());
            let ops = session.ops(&snapshot);
            report.default = Some(DefaultInfo::of(&ops));
            for path in snapshot.config.browsers() {
                let info = session.context.browsers.at(&path);
                let (count, error) = match profiles::of(session.context.browsers, &path) {
                    Ok(list) => (Some(list.len()), None),
                    Err(e) => (None, Some(e.to_string())),
                };
                report.browsers.push(BrowserCheck {
                    name: session.context.browsers.display_name(&path),
                    installed: info.is_some(),
                    local_state: info.map(|i| i.user_data.join("Local State").to_string_lossy().into_owned()),
                    profile_count: count,
                    error,
                    path,
                });
            }
            for rule in ops.rules() {
                let mut problem = |kind: String, message: String| {
                    report.rules.push(RuleProblem {
                        index: rule.index,
                        condition: rule.condition,
                        value: rule.value.clone(),
                        problem: kind,
                        message,
                    });
                };
                if rule.value.is_empty() {
                    problem(
                        "empty_pattern".into(),
                        "The pattern is empty, so the rule never matches.".into(),
                    );
                }
                if let Some(message) = format::problem(rule.profile_status, &rule.destination) {
                    let kind = serde_json::to_value(rule.profile_status)
                        .ok()
                        .and_then(|v| v.as_str().map(str::to_owned));
                    problem(format!("profile_{}", kind.unwrap_or_default()), message);
                }
                if let Some(by) = rule.shadowed_by {
                    problem("unreachable".into(), format!("Never matches: rule {by} always matches first."));
                }
            }
            report.history.enabled = snapshot.config.history_enabled();
        }
        Err(error) => {
            report.config.error = Some(error.to_string());
            report.config.revision = store.current_revision().ok();
        }
    }
    let history = session.history();
    match history.entries() {
        Ok(entries) => report.history.entries = Some(entries.len()),
        Err(e) => report.history.error = Some(e.to_string()),
    }
    report.history.last_write_error = history.last_write_error();
    report.ok = report.config.valid
        && report.default.as_ref().is_some_and(|d| d.profile_status == ProfileStatus::Ok)
        && report.rules.is_empty()
        && report.browsers.iter().all(|b| b.error.is_none())
        && report.history.error.is_none()
        && report.history.last_write_error.is_none();
    let text = text(&report);
    Ok(Output::new(&report, text))
}

fn text(r: &Report) -> String {
    let line = |ok: bool, message: &str| format!("  {} {message}\n", if ok { "✓" } else { "!" });
    let mut text = format!("Configuration: {}\n", r.config.path);
    match &r.config.error {
        Some(error) => text += &line(false, error),
        None => {
            let state = if r.config.exists { "valid" } else { "not created yet; using defaults" };
            let rev = r
                .config
                .revision
                .as_deref()
                .map(|v| format!(", revision {}", format::short(v)))
                .unwrap_or_default();
            text += &line(true, &format!("{state}{rev}"));
        }
    }
    if let Some(d) = &r.default {
        text += &format!("Default: {}\n", d.destination.label());
        text += &line(
            d.profile_status == ProfileStatus::Ok,
            &format::problem(d.profile_status, &d.destination).unwrap_or_else(|| "profile resolves".into()),
        );
    }
    if !r.browsers.is_empty() {
        text += "Browsers:\n";
    }
    for b in &r.browsers {
        let detail = b.error.clone().unwrap_or_else(|| {
            format!(
                "{} profiles, Local State at {}",
                b.profile_count.unwrap_or(0),
                b.local_state.as_deref().unwrap_or("unknown")
            )
        });
        text += &line(b.error.is_none(), &format!("{}  {}  {detail}", b.name, b.path));
    }
    if r.config.valid {
        text += "Rules:\n";
        if r.rules.is_empty() {
            text += &line(true, "every rule resolves and can match");
        }
        for p in &r.rules {
            text += &line(
                false,
                &format!("rule {} ({} {}): {}", p.index, p.condition.as_str(), p.value, p.message),
            );
        }
    }
    text += &format!("History: {}\n", r.history.path);
    let entries = r.history.entries.unwrap_or(0);
    text += &line(
        r.history.error.is_none(),
        &r.history.error.clone().unwrap_or_else(|| {
            format!(
                "{}, {entries} {}",
                if r.history.enabled { "on" } else { "off" },
                if entries == 1 { "entry" } else { "entries" }
            )
        }),
    );
    if let Some(error) = &r.history.last_write_error {
        text += &line(false, &format!("last write failed: {error}"));
    }
    text += &format!("Version: {}\n", r.version);
    text += if r.ok { "No problems found.\n" } else { "Problems found; see the ! lines above.\n" };
    text
}
