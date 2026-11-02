use serde::Serialize;
use switchboard_core::OpError;
use switchboard_core::ops::{Action, DecisionInfo, RouteRequest, RuleInfo, RuleRef};

use super::Output;
use crate::cli::Route;
use crate::format;
use crate::session::Session;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Report {
    url: String,
    action: Action,
    changed: bool,
    written: bool,
    dry_run: bool,
    rule: Option<RuleInfo>,
    before: DecisionInfo,
    after: DecisionInfo,
    shadowed_rules: Vec<RuleRef>,
    revision: String,
}

pub fn run(session: &Session<'_>, command: &Route) -> Result<Output, OpError> {
    let snapshot = session.load()?;
    session.check(&snapshot, &command.change)?;
    let linked = session.link(&command.link, &snapshot.config)?;
    let ops = session.ops(&snapshot);
    let result = ops.route(&RouteRequest {
        url: linked.url.clone(),
        profile: command.profile.clone(),
        browser: command.browser.clone(),
        condition: command.condition.into(),
        value: command.value.clone(),
        allow_shadowing: command.allow_shadowing,
    })?;
    let revision = session.commit(&result.config, &snapshot, &command.change)?;
    let edited = ops.with(result.config.clone());
    let before = ops.decision(&linked.url);
    let after = edited.decision(&linked.url);
    let rule = result.index.map(|i| edited.rules().swap_remove(i));
    let shadowed: Vec<RuleRef> = result.unreachable.iter().map(|u| edited.reference(u.rule)).collect();
    let dry = command.change.dry_run;
    let text = match &rule {
        Some(rule) if result.changed() => {
            let verb = match (result.action, dry) {
                (Action::Added, true) => "Would add",
                (Action::Added, false) => "Added",
                (_, true) => "Would update",
                (_, false) => "Updated",
            };
            format!(
                "{verb} rule {}: {}\n  before: {}\n  after:  {}\n{}{}",
                rule.index,
                format::rule_line(rule),
                format::decision(&before),
                format::decision(&after),
                format::unreachable(&shadowed),
                format::written(dry, &revision)
            )
        }
        _ => format!("Nothing to change: the URL already opens in {}.\n", format::decision(&before)),
    };
    let report = Report {
        url: linked.display,
        action: result.action,
        changed: result.changed(),
        written: result.changed() && !dry,
        dry_run: dry,
        rule,
        before,
        after,
        shadowed_rules: shadowed,
        revision,
    };
    Ok(Output::new(&report, text))
}
