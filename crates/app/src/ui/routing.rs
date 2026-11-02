//! Routing: the ordered rules, and the sheet that adds or edits one.

use rune::{El, col, el, row, text};
use rune_kit::{Dialog, SegmentedControl, TextInput};
use switchboard_core::config::{Condition, Rule};
use switchboard_core::ops;
use switchboard_core::{profiles, shadowing};

use super::controls::{
    Choice, DESCRIPTION, Kind, METRICS, Paint, button, card, note, page, scroll_body, select, setting_row,
};
use super::{Draft, Open, Ui};

pub fn pane(ui: &Ui, p: Paint, _layer: &mut Vec<El>) -> El {
    let e = &ui.editor;
    let c = &e.config;
    let hidden: Vec<_> = shadowing::unreachable(&c.rules);
    let mut rows = Vec::new();
    for (i, rule) in c.rules.iter().enumerate() {
        rows.push(rule_row(ui, p, i, rule, hidden.iter().find(|u| u.rule == i).map(|u| u.by)));
    }
    let list = if rows.is_empty() {
        card(
            p,
            "rules",
            vec![
                note("empty", "No rules yet. Every link opens in the default destination.", p.muted())
                    .py(16.0),
            ],
        )
    } else {
        card(p, "rules", rows)
    };
    let add = button(p, "add-rule", "Add rule…", Kind::Secondary, |ui: &mut Ui, tx| {
        tx.instant();
        ui.open = None;
        ui.draft = Some(Draft::new_rule());
    });
    scroll_body(
        "routing",
        page("routing-page")
            .child(note("explain", "Rules are checked in order; the first match wins.", p.muted()))
            .child(list)
            .child(row().key("routing-actions").px(METRICS.row_px).child(add)),
    )
}

fn rule_row(ui: &Ui, p: Paint, index: usize, rule: &Rule, hidden_by: Option<usize>) -> El {
    let e = &ui.editor;
    let browser = e.config.browser_of(rule);
    let destination = format!(
        "{} · {}{}",
        e.browser_name(browser),
        e.profile_name(browser, &rule.profile),
        if rule.browser.is_none() { "  (default browser)" } else { "" }
    );
    let id = rule.id;
    let mut copy = col()
        .key("copy")
        .grow(1.0)
        .shrink()
        .min_w(0.0)
        .gap(2.0)
        .child(
            row()
                .key("pattern")
                .gap(8.0)
                .center_y()
                .child(
                    text(format!("{}", index + 1)).key("index").font(p.k.ty.small).color(p.muted()).w(16.0),
                )
                .child(
                    text(rule.condition.label())
                        .key("condition")
                        .font(p.k.ty.small_medium)
                        .color(p.muted())
                        .w(60.0),
                )
                .child(
                    text(if rule.value.is_empty() { "(empty, ignored)" } else { &rule.value })
                        .key("value")
                        .font(p.k.ty.ui)
                        .color(p.text())
                        .truncate()
                        .shrink(),
                ),
        )
        .child(
            text(destination)
                .key("destination")
                .font(DESCRIPTION)
                .color(p.muted())
                .ml(PATTERN_INDENT)
                .truncate(),
        );
    let resolves = profiles::directory(&rule.profile, &e.profiles_of(browser)).is_ok();
    if !resolves {
        copy = copy.child(
            text("This profile isn't available. Edit the rule to choose another.")
                .key("problem")
                .font(DESCRIPTION)
                .color(p.danger())
                .ml(PATTERN_INDENT),
        );
    }
    if let Some(by) = hidden_by {
        copy = copy.child(
            text(format!("Never matches: rule {} always matches first.", by + 1))
                .key("hidden")
                .font(DESCRIPTION)
                .color(p.danger())
                .ml(PATTERN_INDENT),
        );
    }
    let last = index + 1 == e.config.rules.len();
    let actions = row()
        .key("actions")
        .gap(4.0)
        .child(small(p, "up", "↑", index > 0, move |ui| ui.editor.move_rule(id, -1)))
        .child(small(p, "down", "↓", !last, move |ui| ui.editor.move_rule(id, 1)))
        .child(button(p, "edit", "Edit…", Kind::Secondary, move |ui: &mut Ui, tx| {
            tx.instant();
            if let Some(r) = ui.editor.config.rules.iter().find(|r| r.id == id) {
                ui.draft = Some(Draft::editing(r));
            }
        }))
        .child(button(p, "delete", "Delete", Kind::Secondary, move |ui: &mut Ui, _| {
            ui.editor.delete_rule(id)
        }));
    row()
        .key(format!("rule-{index}"))
        .label(format!("Rule {}: {} {}", index + 1, rule.condition.as_str(), rule.value))
        .w_full()
        .min_h(METRICS.row_h + 8.0)
        .px(METRICS.row_px)
        .py(8.0)
        .gap(12.0)
        .center_y()
        .child(copy)
        .child(actions)
}

/// Where a rule's pattern starts: past its number and condition.
const PATTERN_INDENT: f32 = 92.0;

fn small(p: Paint, key: &str, label: &str, enabled: bool, press: impl Fn(&mut Ui) + 'static) -> El {
    rune_kit::Button::new(label)
        .variant(rune_kit::ButtonVariant::Ghost)
        .disabled(!enabled)
        .on_press(press)
        .build(p.k)
        .key(key)
        .label(if key == "up" { "Move up" } else { "Move down" })
}

/// The add/edit sheet, mounted in the overlay layer.
#[expect(
    clippy::expect_used,
    reason = "the field's handler only runs while the sheet, and so its draft, exists"
)]
pub fn sheet(ui: &Ui, p: Paint, layer: &mut Vec<El>) {
    let Some(draft) = &ui.draft else { return };
    let e = &ui.editor;
    let default_browser = e.config.browser.clone();

    let labels: Vec<&str> = Condition::ALL.iter().map(|c| c.label()).collect();
    let selected = Condition::ALL.iter().position(|c| *c == draft.condition);
    let condition = SegmentedControl::new(&labels, selected)
        .fit()
        .on_pick(|ui: &mut Ui, i, tx| {
            tx.instant();
            if let Some(d) = &mut ui.draft {
                d.condition = Condition::ALL[i];
                d.error = None;
            }
        })
        .build(p.k)
        .key("draft-condition");

    let hint = match draft.condition {
        Condition::Domain => "A host such as github.com; it also matches subdomains",
        Condition::Contains => "Text anywhere in the link, ignoring case",
        Condition::Exact => "The complete link, ignoring case",
    };
    let value = TextInput::new(&draft.value)
        .placeholder(match draft.condition {
            Condition::Domain => "github.com",
            Condition::Contains => "github.com/acme",
            Condition::Exact => "https://example.com/page",
        })
        .on_edit(|ui: &mut Ui| &mut ui.draft.as_mut().expect("the sheet is open").value)
        .on_submit(|ui: &mut Ui, tx| done(ui, tx))
        .build(p.k)
        .key("draft-value")
        .w(METRICS.select_w);

    let mut browsers = vec![{
        let name = format!("Default browser ({})", e.browser_name(&default_browser));
        let d = default_browser.clone();
        Choice::new(name, draft.browser.is_none(), move |ui: &mut Ui| {
            if let Some(dr) = &mut ui.draft {
                dr.select_browser(None, &d);
            }
        })
    }];
    for b in &e.installed {
        let locator = b.locator.clone();
        let d = default_browser.clone();
        let chosen = draft.browser.as_deref().is_some_and(|x| e.browsers.standardize(x) == b.locator);
        browsers.push(Choice::new(b.name.clone(), chosen, move |ui: &mut Ui| {
            if let Some(dr) = &mut ui.draft {
                dr.select_browser(Some(locator.clone()), &d);
            }
        }));
    }
    let target = draft.browser.clone().unwrap_or(default_browser.clone());
    let browser_label = match &draft.browser {
        None => format!("Default browser ({})", e.browser_name(&default_browser)),
        Some(b) => e.browser_name(b),
    };
    let browser = select(p, Open::DraftBrowser, &browser_label, ui.open, browsers, layer);

    let choices: Vec<Choice> = e
        .profiles_of(&target)
        .into_iter()
        .map(|pr| {
            let dir = pr.directory.clone();
            let label = if pr.name == pr.directory {
                pr.name.clone()
            } else {
                format!("{} ({})", pr.name, pr.directory)
            };
            Choice::new(label, draft.profile == pr.directory, move |ui: &mut Ui| {
                if let Some(d) = &mut ui.draft {
                    d.profile = dir.clone();
                    d.error = None;
                }
            })
        })
        .collect();
    let profile =
        select(p, Open::DraftProfile, &e.profile_name(&target, &draft.profile), ui.open, choices, layer);

    let mut body = col()
        .key("draft-body")
        .w_full()
        .px(4.0)
        .pb(12.0)
        .child(setting_row(p, "draft-condition-row", "Match", None, condition))
        .child(setting_row(p, "draft-value-row", "Pattern", Some(hint), value))
        .child(setting_row(p, "draft-browser-row", "Browser", None, browser))
        .child(setting_row(p, "draft-profile-row", "Profile", None, profile));
    if let Some(error) = &draft.error {
        body = body.child(note("draft-error", error, p.danger()));
    }
    body = body.child(
        row()
            .key("draft-actions")
            .w_full()
            .px(METRICS.row_px)
            .pt(8.0)
            .gap(8.0)
            .child(el().key("spacer").grow(1.0))
            .child(button(p, "draft-cancel", "Cancel", Kind::Secondary, |ui: &mut Ui, tx| {
                tx.instant();
                ui.draft = None;
                ui.open = None;
            }))
            .child(
                button(p, "draft-done", "Done", Kind::Primary, |ui: &mut Ui, tx| done(ui, tx))
                    .default_button(),
            ),
    );
    Dialog::new("rule-sheet", if draft.is_new { "Add rule" } else { "Edit rule" })
        .open(true)
        .width(520.0)
        .fit()
        .click_outside(false)
        // Escape with a menu open closes only the menu.
        .on_close(|ui: &mut Ui| {
            if ui.open.take().is_none() {
                ui.draft = None;
            }
        })
        .child(body)
        .build(p.k, layer);
}

/// Validates the draft and saves it into the config, or shows why not.
fn done(ui: &mut Ui, tx: &mut rune::Tx) {
    let Some(draft) = &mut ui.draft else { return };
    let value = draft.value.text.trim().to_owned();
    let check = ops::pattern(&value).and_then(|v| {
        if draft.condition == Condition::Domain { ops::validate_domain(&v).map(|_| v) } else { Ok(v) }
    });
    let value = match check {
        Ok(v) => v,
        Err(e) => {
            draft.error = Some(e.message.replace("--value", "The pattern"));
            return;
        }
    };
    if draft.profile.is_empty() {
        draft.error = Some("Choose a profile.".into());
        return;
    }
    let mut rule = Rule::new(draft.condition, value, draft.profile.clone());
    rule.id = draft.id;
    rule.browser = draft.browser.clone();
    tx.instant();
    if ui.editor.commit_rule(rule) {
        ui.draft = None;
        ui.open = None;
    }
}
