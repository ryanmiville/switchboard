use serde::Serialize;
use switchboard_core::OpError;
use switchboard_core::ops::{Action, BrowserChoice, Ops, RuleChange, RuleInfo, RuleRef, RuleUpdate};
use switchboard_core::store::Snapshot;

use super::{DefaultInfo, HistoryChangeReport, Output, history_changes};
use crate::cli::{Change, Default, Rules, RulesUpdate};
use crate::format;
use crate::session::Session;

#[derive(Serialize)]
struct ListReport {
    rules: Vec<RuleInfo>,
    default: DefaultInfo,
    revision: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ChangeReport {
    action: Action,
    changed: bool,
    written: bool,
    dry_run: bool,
    rule: RuleInfo,
    #[serde(skip_serializing_if = "Option::is_none")]
    previous: Option<RuleInfo>,
    #[serde(skip_serializing_if = "Option::is_none")]
    from: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    to: Option<usize>,
    shadowed_rules: Vec<RuleRef>,
    /// False when history is off or unreadable, so no recent links could be checked.
    history_checked: bool,
    history_changes: Vec<HistoryChangeReport>,
    revision: String,
}

pub fn run(session: &Session<'_>, command: &Rules) -> Result<Output, OpError> {
    match command {
        Rules::List => list(session),
        Rules::Update(update) => self::update(session, update),
        Rules::Move { from, to, change } => {
            let (snapshot, ops) = start(session, change)?;
            let result = ops.move_rule(*from, *to)?;
            let rule = ops.with(result.config.clone()).rules().swap_remove(to - 1);
            let text_rule = format::rule_line(&rule);
            finish(
                session,
                &snapshot,
                &ops,
                result,
                change,
                rule,
                None,
                Some((*from, *to)),
                |changed, dry| {
                    if changed {
                        format!(
                            "{} rule {from} to position {to}: {text_rule}\n",
                            if dry { "Would move" } else { "Moved" }
                        )
                    } else {
                        format!("Nothing to change: rule {from} is already at position {to}.\n")
                    }
                },
            )
        }
        Rules::Remove { position, change } => {
            let (snapshot, ops) = start(session, change)?;
            let result = ops.remove_rule(*position)?;
            let rule = ops.rules().swap_remove(position - 1);
            let line = format!("rule {}: {}", rule.index, format::rule_line(&rule));
            finish(session, &snapshot, &ops, result, change, rule, None, None, |_, dry| {
                format!("{} {line}\n", if dry { "Would remove" } else { "Removed" })
            })
        }
    }
}

fn start<'a>(session: &Session<'a>, change: &Change) -> Result<(Snapshot, Ops<'a>), OpError> {
    let snapshot = session.load()?;
    session.check(&snapshot, change)?;
    let ops = session.ops(&snapshot);
    Ok((snapshot, ops))
}

#[expect(clippy::too_many_arguments, reason = "one shared tail for the three position-based commands")]
fn finish(
    session: &Session<'_>,
    snapshot: &Snapshot,
    ops: &Ops<'_>,
    result: RuleChange,
    change: &Change,
    rule: RuleInfo,
    previous: Option<RuleInfo>,
    moved: Option<(usize, usize)>,
    headline: impl FnOnce(bool, bool) -> String,
) -> Result<Output, OpError> {
    let revision = session.commit(&result.config, snapshot, change)?;
    let edited = ops.with(result.config.clone());
    let shadowed: Vec<RuleRef> = result.unreachable.iter().map(|u| edited.reference(u.rule)).collect();
    let (checked, changes) = history_changes(session, ops, &result.config);
    let changed = result.changed();
    let mut text = headline(changed, change.dry_run);
    if changed {
        if let Some(previous) = &previous {
            text += &format!("  was: {}\n", format::rule_line(previous));
        }
        text += &format::unreachable(&shadowed);
        text += &format::history_changes(&changes, checked);
        text += &format::written(change.dry_run, &revision);
    }
    let report = ChangeReport {
        action: result.action,
        changed,
        written: changed && !change.dry_run,
        dry_run: change.dry_run,
        rule,
        previous,
        from: moved.map(|m| m.0),
        to: moved.map(|m| m.1),
        shadowed_rules: shadowed,
        history_checked: checked,
        history_changes: changes,
        revision,
    };
    Ok(Output::new(&report, text))
}

fn list(session: &Session<'_>) -> Result<Output, OpError> {
    let snapshot = session.load()?;
    let ops = session.ops(&snapshot);
    let rules = ops.rules();
    let default = DefaultInfo::of(&ops);
    let mut text = format!("Default: {}\n", default.destination.label());
    if let Some(problem) = format::problem(default.profile_status, &default.destination) {
        text += &format!("  ! {problem}\n");
    }
    if rules.is_empty() {
        text += "No rules. Every link uses the default destination.\n";
    }
    let width = rules.iter().map(|r| r.value.chars().count().max(1)).max().unwrap_or(0).min(40);
    for rule in &rules {
        let pattern = if rule.value.is_empty() { "(empty, ignored)" } else { &rule.value };
        text += &format!(
            "{}{}{}  → {}{}\n",
            format::padded(&rule.index.to_string(), 3),
            format::padded(rule.condition.as_str(), 10),
            format::padded(pattern, width),
            rule.destination.label(),
            if rule.browser.is_none() { "  (default browser)" } else { "" }
        );
        if let Some(problem) = format::problem(rule.profile_status, &rule.destination) {
            text += &format!("     ! {problem}\n");
        }
        if let Some(by) = rule.shadowed_by {
            text += &format!("     ! Never matches: rule {by} always matches first.\n");
        }
    }
    text += &format!("Revision {}\n", format::short(&snapshot.revision));
    Ok(Output::new(&ListReport { rules, default, revision: snapshot.revision }, text))
}

fn update(session: &Session<'_>, command: &RulesUpdate) -> Result<Output, OpError> {
    let (snapshot, ops) = start(session, &command.change)?;
    let browser = if command.default_browser {
        Some(BrowserChoice::Default)
    } else {
        command.browser.clone().map(BrowserChoice::Browser)
    };
    let result = ops.update_rule(
        command.position,
        &RuleUpdate {
            profile: command.profile.clone(),
            browser,
            condition: command.condition.map(Into::into),
            value: command.value.clone(),
            allow_shadowing: command.allow_shadowing,
        },
    )?;
    let previous = ops.rules().swap_remove(command.position - 1);
    let rule = ops.with(result.config.clone()).rules().swap_remove(command.position - 1);
    let line = format::rule_line(&rule);
    let index = rule.index;
    finish(session, &snapshot, &ops, result, &command.change, rule, Some(previous), None, |changed, dry| {
        if changed {
            format!("{} rule {index}: {line}\n", if dry { "Would update" } else { "Updated" })
        } else {
            format!("Nothing to change: rule {index} is already {line}.\n")
        }
    })
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DefaultReport {
    destination: switchboard_core::ops::DestinationInfo,
    profile_status: switchboard_core::ops::ProfileStatus,
    revision: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DefaultChangeReport {
    changed: bool,
    written: bool,
    dry_run: bool,
    before: DefaultInfo,
    destination: switchboard_core::ops::DestinationInfo,
    profile_status: switchboard_core::ops::ProfileStatus,
    history_checked: bool,
    history_changes: Vec<HistoryChangeReport>,
    revision: String,
}

pub fn default(session: &Session<'_>, command: &Default) -> Result<Output, OpError> {
    let snapshot = session.load()?;
    let ops = session.ops(&snapshot);
    let current = DefaultInfo::of(&ops);
    if command.browser.is_none() && command.profile.is_none() {
        let mut text = format!("Default: {}\n", current.destination.label());
        if let Some(problem) = format::problem(current.profile_status, &current.destination) {
            text += &format!("  ! {problem}\n");
        }
        let report = DefaultReport {
            destination: current.destination,
            profile_status: current.profile_status,
            revision: snapshot.revision,
        };
        return Ok(Output::new(&report, text));
    }
    session.check(&snapshot, &command.change)?;
    let result = ops.set_default(command.browser.as_deref(), command.profile.as_deref())?;
    let revision = session.commit(&result.config, &snapshot, &command.change)?;
    let updated = DefaultInfo::of(&ops.with(result.config.clone()));
    let (checked, changes) = history_changes(session, &ops, &result.config);
    let dry = command.change.dry_run;
    let text = if result.changed {
        format!(
            "{} the default to {}\n  was: {}\n{}{}",
            if dry { "Would change" } else { "Changed" },
            updated.destination.label(),
            current.destination.label(),
            format::history_changes(&changes, checked),
            format::written(dry, &revision)
        )
    } else {
        format!("Nothing to change: the default is already {}.\n", current.destination.label())
    };
    let report = DefaultChangeReport {
        changed: result.changed,
        written: result.changed && !dry,
        dry_run: dry,
        before: current,
        destination: updated.destination,
        profile_status: updated.profile_status,
        history_checked: checked,
        history_changes: changes,
        revision,
    };
    Ok(Output::new(&report, text))
}
