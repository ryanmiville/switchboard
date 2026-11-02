//! Running a parsed command line: dispatch, and the report types shared by several commands.

mod config;
mod doctor;
mod explain;
mod history;
mod picker;
mod profiles;
mod route;
mod rules;
mod skill;

use std::ffi::OsString;

use clap::Parser;
use serde::Serialize;
use switchboard_core::config::Config;
use switchboard_core::ops::{DecisionInfo, DestinationInfo, Ops, ProfileStatus};
use switchboard_core::store::Snapshot;
use switchboard_core::{Code, OpError};

use crate::Outcome;
use crate::cli::{Cli, Command};
use crate::format;
use crate::session::{Context, Session};

/// What a command prints: a JSON report for `--json`, text otherwise.
pub struct Output {
    pub json: serde_json::Value,
    pub text: String,
}

impl Output {
    pub fn new(report: &impl Serialize, text: String) -> Output {
        Output { json: serde_json::to_value(report).unwrap_or_default(), text }
    }
}

pub fn run(args: Vec<OsString>, context: &Context<'_>) -> Outcome {
    let json = args.iter().any(|a| a == "--json");
    let cli = match Cli::try_parse_from(args) {
        Ok(cli) => cli,
        Err(error) => {
            let status = error.exit_code() as u8;
            let rendered = error.render().to_string();
            if status == 0 {
                return Outcome { status, stdout: rendered, stderr: String::new() };
            }
            if json {
                // The message without clap's usage and help hints, on one line.
                let message: Vec<&str> = rendered
                    .lines()
                    .take_while(|l| !l.starts_with("Usage:") && !l.starts_with("For more information"))
                    .map(str::trim)
                    .filter(|l| !l.is_empty())
                    .collect();
                let first = message.join(" ").trim_start_matches("error: ").to_owned();
                return Outcome::failure(&OpError::invalid(first), true, context.terminal);
            }
            return Outcome { status, stdout: String::new(), stderr: rendered };
        }
    };
    let session = Session::new(context, &cli.global);
    let result = match &cli.command {
        Command::Explain(c) => explain::run(&session, c),
        Command::Route(c) => route::run(&session, c),
        Command::Rules(c) => rules::run(&session, c),
        Command::Default(c) => rules::default(&session, c),
        Command::Profiles(c) => profiles::run(&session, c),
        Command::History(c) => history::run(&session, c),
        Command::Picker(c) => picker::run(&session, c),
        Command::Config => config::run(&session),
        Command::Doctor => doctor::run(&session),
        Command::Skill(c) => skill::run(&session, c),
    };
    match result {
        Ok(output) => Outcome {
            status: 0,
            stdout: if cli.global.json { format::json(&output.json, context.terminal) } else { output.text },
            stderr: String::new(),
        },
        Err(error) => Outcome::failure(&error, cli.global.json, context.terminal),
    }
}

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct DefaultInfo {
    pub destination: DestinationInfo,
    pub profile_status: ProfileStatus,
}

impl DefaultInfo {
    pub fn of(ops: &Ops<'_>) -> DefaultInfo {
        let (destination, profile_status) = ops.describe(&ops.config.default_destination());
        DefaultInfo { destination, profile_status }
    }
}

#[derive(Serialize, Clone, Debug)]
pub struct HistoryChangeReport {
    pub id: String,
    pub url: String,
    pub before: DecisionInfo,
    pub after: DecisionInfo,
}

/// Recent links whose destination `edited` would change, and whether history could be checked.
pub fn history_changes(
    session: &Session<'_>,
    ops: &Ops<'_>,
    edited: &Config,
) -> (bool, Vec<HistoryChangeReport>) {
    let Some(entries) = session.recent_history(&ops.config) else { return (false, Vec::new()) };
    let changes = ops
        .history_changes(edited, &entries)
        .into_iter()
        .map(|c| HistoryChangeReport {
            id: c.entry.id.clone(),
            url: c.entry.redacted_url(),
            before: c.before,
            after: c.after,
        })
        .collect();
    (true, changes)
}

/// The common shape of a settings change made by `history on/off` and `picker`.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SettingChange<T: Serialize> {
    pub changed: bool,
    pub written: bool,
    pub dry_run: bool,
    pub value: T,
    pub revision: String,
}

/// Applies `edit` to the loaded config and commits it.
pub fn change_setting<T: Serialize>(
    session: &Session<'_>,
    change: &crate::cli::Change,
    edit: impl FnOnce(&Ops<'_>, &mut Config) -> Result<(), OpError>,
    value: impl FnOnce(&Config) -> T,
    describe: impl FnOnce(&Config) -> String,
) -> Result<Output, OpError> {
    let snapshot: Snapshot = session.load()?;
    session.check(&snapshot, change)?;
    let ops = session.ops(&snapshot);
    let mut edited = snapshot.config.clone();
    edit(&ops, &mut edited)?;
    let changed = edited != snapshot.config;
    let revision = session.commit(&edited, &snapshot, change)?;
    let text = if changed {
        format!(
            "{} {}\n{}",
            if change.dry_run { "Would set" } else { "Set" },
            describe(&edited),
            format::written(change.dry_run, &revision)
        )
    } else {
        format!("Nothing to change: {}\n", describe(&edited))
    };
    let report = SettingChange {
        changed,
        written: changed && !change.dry_run,
        dry_run: change.dry_run,
        value: value(&edited),
        revision,
    };
    Ok(Output::new(&report, text))
}

pub fn write_failed(what: &str, error: impl std::fmt::Display) -> OpError {
    OpError::new(Code::WriteFailed, format!("{what} {error}"))
}
