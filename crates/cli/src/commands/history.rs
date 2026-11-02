use serde::Serialize;
use switchboard_core::OpError;
use switchboard_core::config::HistorySettings;
use switchboard_core::history::Outcome as Launch;

use super::explain::EntryReport;
use super::{Output, change_setting, write_failed};
use crate::cli::{History, HistoryAction, HistoryList};
use crate::format;
use crate::session::Session;

#[derive(Serialize)]
struct ListReport {
    path: String,
    enabled: bool,
    entries: Vec<EntryReport>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ClearReport {
    path: String,
    entries: usize,
    dry_run: bool,
}

pub fn run(session: &Session<'_>, command: &History) -> Result<Output, OpError> {
    match &command.action {
        None => list(session, &command.list),
        Some(HistoryAction::List(options)) => list(session, options),
        Some(HistoryAction::Clear { dry_run }) => {
            let store = session.history();
            let count = if *dry_run { store.entries().map(|e| e.len()) } else { store.clear() }
                .map_err(|e| write_failed("The history couldn't be cleared.", e))?;
            let noun = if count == 1 { "entry" } else { "entries" };
            let text =
                format!("{} {count} history {noun}.\n", if *dry_run { "Would clear" } else { "Cleared" });
            let path = session.history_path.to_string_lossy().into_owned();
            Ok(Output::new(&ClearReport { path, entries: count, dry_run: *dry_run }, text))
        }
        Some(HistoryAction::On(change)) | Some(HistoryAction::Off(change)) => {
            let on = matches!(command.action, Some(HistoryAction::On(_)));
            change_setting(
                session,
                change,
                // Omitted means on, which keeps the file minimal.
                |_, config| {
                    config.history = if on { None } else { Some(HistorySettings { enabled: false }) };
                    Ok(())
                },
                |config| serde_json::json!({ "enabled": config.history_enabled() }),
                |config| format!("history {}.", if config.history_enabled() { "on" } else { "off" }),
            )
        }
    }
}

fn list(session: &Session<'_>, options: &HistoryList) -> Result<Output, OpError> {
    let snapshot = session.load()?;
    let entries: Vec<EntryReport> = session
        .history_entries(&snapshot.config)?
        .iter()
        .take(options.limit as usize)
        .map(|e| EntryReport::new(e, options.full_urls, session))
        .collect();
    let now = session.context.now;
    let ages: Vec<String> = entries
        .iter()
        .map(|e| {
            switchboard_core::time::Timestamp::parse(&e.time).map_or_else(|| e.time.clone(), |t| t.ago(now))
        })
        .collect();
    let age_width = ages.iter().map(|a| a.chars().count()).max().unwrap_or(0) + 2;
    let url_width = entries.iter().map(|e| e.url.chars().count()).max().unwrap_or(0).min(60) + 2;
    let mut text = if entries.is_empty() { "No links in history yet.\n".to_owned() } else { String::new() };
    for (entry, age) in entries.iter().zip(&ages) {
        let failed = match entry.result {
            Launch::Failed => format!("  (failed: {})", entry.error.as_deref().unwrap_or("unknown error")),
            Launch::Launched => String::new(),
        };
        text += &format!(
            "{}  {}{}{} → {}{failed}\n",
            entry.id,
            format::padded(age, age_width),
            format::padded(&entry.url, url_width),
            entry.how(),
            entry.destination()
        );
    }
    let path = session.history_path.to_string_lossy().into_owned();
    Ok(Output::new(&ListReport { path, enabled: true, entries }, text))
}
