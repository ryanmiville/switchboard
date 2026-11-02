//! Routing: the ordered rules as a table (drag a row to change its priority, double-click or
//! Return to edit, + and − below), a field to test a link, and the sheet that adds or edits one.

use rune::{Anim, Drag, El, Phase, Tx, col, el, row, text};
use rune_kit::{Button, ButtonVariant, TextInput};
use switchboard_core::config::{Config, Rule};
use switchboard_core::{profiles, router, shadowing};

use super::controls::{DESCRIPTION, Kind, METRICS, Paint, button, card, note, page, scroll_body};
use super::{Draft, RuleDrag, Ui};
use rune_kit::{Dialog, SegmentedControl};
use switchboard_core::config::Condition;
use switchboard_core::ops;

use super::Open;
use super::controls::{Choice, select, setting_row};

/// One rule row's height. Rows share it, so a drag knows where it is from how far it moved.
pub const ROW_H: f32 = 40.0;
/// Points the pointer travels before a press on a row becomes a drag.
const SLOP: f32 = 4.0;
/// A browser icon's size, in points.
pub const ICON: f32 = 16.0;
const COL_INDEX: f32 = 28.0;
const COL_MATCH: f32 = 76.0;
const COL_PATTERN: f32 = 250.0;

pub fn pane(ui: &Ui, p: Paint, _layer: &mut Vec<El>) -> El {
    scroll_body(
        "routing",
        page("routing-page")
            .child(
                col()
                    .key("rules-section")
                    .w_full()
                    .gap(METRICS.label_gap)
                    .child(
                        text("Routing rules")
                            .key("label")
                            .font(p.k.ty.small_medium)
                            .color(p.muted())
                            .mx(METRICS.row_px),
                    )
                    .child(
                        text("First match wins. Drag rules to change their priority.")
                            .key("hint")
                            .font(DESCRIPTION)
                            .color(p.muted())
                            .mx(METRICS.row_px),
                    )
                    .child(table(ui, p)),
            )
            .child(test_link(ui, p)),
    )
}

fn table(ui: &Ui, p: Paint) -> El {
    let k = p.k;
    let rules = &ui.editor.config.rules;
    let hidden = shadowing::unreachable(rules);
    let header = row()
        .key("rules-header")
        .w_full()
        .h(30.0)
        .px(METRICS.row_px)
        .gap(8.0)
        .center_y()
        .child(head(p, "#", Some(COL_INDEX)))
        .child(head(p, "URL pattern", Some(COL_PATTERN)))
        .child(head(p, "Match", Some(COL_MATCH)))
        .child(head(p, "Destination", None));
    let mut list = col().key("rules").w_full().clip_rounded(0.0);
    if rules.is_empty() {
        list = list.child(
            note("empty", "No rules yet. Every link opens in the default destination.", p.muted()).py(14.0),
        );
    }
    for (i, rule) in rules.iter().enumerate() {
        let hidden_by = hidden.iter().find(|u| u.rule == i).map(|u| u.by);
        list = list.child(rule_row(ui, p, i, rule, hidden_by));
    }
    let selected = ui.selected_index().is_some();
    let footer = row()
        .key("rules-footer")
        .w_full()
        .h(34.0)
        .px(8.0)
        .gap(2.0)
        .center_y()
        .child(
            Button::new("+")
                .variant(ButtonVariant::Ghost)
                .help("Add a rule")
                .on_press_tx(|ui: &mut Ui, tx| {
                    tx.instant();
                    ui.open = None;
                    ui.draft = Some(Draft::new_rule());
                })
                .build(k)
                .key("add-rule")
                .label("Add rule"),
        )
        .child(
            Button::new("−")
                .variant(ButtonVariant::Ghost)
                .disabled(!selected)
                .help("Remove the selected rule")
                .on_press(|ui: &mut Ui| ui.delete_selected())
                .build(k)
                .key("remove-rule")
                .label("Remove rule"),
        )
        .child(el().key("spacer").grow(1.0))
        .child(
            Button::new("Edit rule…")
                .variant(ButtonVariant::Ghost)
                .disabled(!selected)
                .on_press_tx(|ui: &mut Ui, tx| ui.edit_selected(tx))
                .build(k)
                .key("edit-rule"),
        );
    let sep = |key: &str| el().key(key.to_owned()).w_full().h(p.hair).fill(k.c.border_muted);
    card(
        p,
        "rules-table",
        vec![
            col()
                .key("table")
                .w_full()
                .child(header)
                .child(sep("header-sep"))
                .child(list)
                .child(sep("footer-sep"))
                .child(footer),
        ],
    )
}

fn head(p: Paint, title: &str, width: Option<f32>) -> El {
    let t = text(title)
        .key(format!("head-{}", title.to_lowercase().replace([' ', '#'], "")))
        .font(p.k.ty.small_medium)
        .color(p.muted());
    match width {
        Some(w) => t.w(w),
        None => t.grow(1.0),
    }
}

fn rule_row(ui: &Ui, p: Paint, index: usize, rule: &Rule, hidden_by: Option<usize>) -> El {
    let k = p.k;
    let e = &ui.editor;
    let browser = e.config.browser_of(rule).to_owned();
    let id = rule.id;
    let selected = ui.selected == Some(id);
    let resolves = profiles::directory(&rule.profile, &e.profiles_of(&browser)).is_ok();
    let shift = shift(ui.drag, index);
    let dragging = ui.drag.is_some_and(|d| d.from == index && d.dy.abs() >= SLOP);

    let pattern = if rule.value.is_empty() { "(empty, ignored)".to_owned() } else { rule.value.clone() };
    let mut pattern_cell = row()
        .key("pattern")
        .w(COL_PATTERN)
        .gap(6.0)
        .center_y()
        .child(text(pattern).key("value").font(k.ty.ui).color(p.text()).truncate().shrink());
    if let Some(by) = hidden_by {
        pattern_cell = pattern_cell.child(
            text("never matches")
                .key("hidden")
                .font(DESCRIPTION)
                .color(p.danger())
                .help(format!("Rule {} always matches first.", by + 1)),
        );
    }
    let destination = format!("{} · {}", e.browser_name(&browser), e.profile_name(&browser, &rule.profile));
    let mut dest_cell = row()
        .key("destination")
        .grow(1.0)
        .shrink()
        .min_w(0.0)
        .gap(8.0)
        .center_y()
        .child(icon(ui, &browser))
        .child(
            text(destination)
                .key("label")
                .font(k.ty.ui)
                .color(if resolves { p.text() } else { p.danger() })
                .truncate()
                .shrink(),
        );
    if rule.browser.is_none() {
        dest_cell =
            dest_cell.child(text("default browser").key("inherits").font(DESCRIPTION).color(p.muted()));
    }

    let fill = if selected {
        k.c.layer_03
    } else if index % 2 == 1 {
        k.c.layer_01
    } else {
        k.c.bg_base
    };
    let mut r = row()
        .key(format!("rule-{}", rule_key(rule)))
        .role("row")
        .label(format!(
            "Rule {}: {} {} → {}",
            index + 1,
            rule.condition.as_str(),
            rule.value,
            e.browser_name(&browser)
        ))
        .w_full()
        .h(ROW_H)
        .px(METRICS.row_px)
        .gap(8.0)
        .center_y()
        .fill(fill)
        .offset(0.0, shift)
        .on_press_tx(move |ui: &mut Ui, tx| {
            tx.instant();
            ui.selected = Some(id);
        })
        .on_double_press_tx(move |ui: &mut Ui, tx| {
            ui.selected = Some(id);
            ui.edit_selected(tx);
        })
        .on_drag(move |ui: &mut Ui, d: &mut Drag, tx| drag(ui, d, tx, index, id))
        .child(text(format!("{}", index + 1)).key("index").font(k.ty.small).color(p.muted()).w(COL_INDEX))
        .child(pattern_cell)
        .child(text(rule.condition.label()).key("condition").font(k.ty.small).color(p.muted()).w(COL_MATCH))
        .child(dest_cell);
    if dragging {
        // The row under the hand follows it exactly; the rows it passes slide aside.
        r = r
            .offset_motion(Anim::INSTANT)
            .box_shadow(k.elevation.overlay.first().copied().unwrap_or_default())
            .fill(k.c.layer_03);
    }
    r
}

/// A stable key for a rule's row, so rows keep their identity when they move.
pub fn rule_key(rule: &Rule) -> String {
    format!("{:?}", rule.id).chars().filter(char::is_ascii_digit).collect()
}

/// How far row `index` sits from its place during a drag.
fn shift(drag: Option<RuleDrag>, index: usize) -> f32 {
    let Some(d) = drag.filter(|d| d.dy.abs() >= SLOP) else { return 0.0 };
    if index == d.from {
        d.dy
    } else if d.from < index && index <= d.to {
        -ROW_H
    } else if d.to <= index && index < d.from {
        ROW_H
    } else {
        0.0
    }
}

fn drag(ui: &mut Ui, d: &mut Drag, tx: &mut Tx, index: usize, id: switchboard_core::config::RuleId) {
    let count = ui.editor.config.rules.len();
    match d.phase {
        Phase::Down => {
            ui.selected = Some(id);
            tx.instant();
        }
        Phase::Move => {
            if ui.drag.is_none() && d.dy.abs() < SLOP {
                return;
            }
            let to =
                (index as f32 + (d.dy / ROW_H).round()).clamp(0.0, count.saturating_sub(1) as f32) as usize;
            ui.drag = Some(RuleDrag { from: index, to, dy: d.dy });
        }
        Phase::Up => {
            let Some(drop) = ui.drag.take() else { return };
            // The drop lands at once: the hand put it there.
            tx.instant();
            if !d.cancelled() && drop.to != drop.from {
                ui.editor.move_rule_to(id, drop.to);
            }
        }
    }
}

/// The browser's icon, or an empty square until it has decoded (or when it has none).
fn icon(ui: &Ui, browser: &str) -> El {
    let slot = el().key("icon").size(ICON, ICON).radius(3.0);
    let Some(cache) = &ui.icons else { return slot };
    let Some(info) = ui.editor.browsers.at(browser) else { return slot };
    let image = cache.app_icon(&info.locator, ICON);
    if image.error().is_some() {
        return slot;
    }
    slot.pixels(image.pixels())
}

/// "Test a URL": which rule a link matches and where it would open, without opening it.
fn test_link(ui: &Ui, p: Paint) -> El {
    let k = p.k;
    let field = TextInput::new(&ui.test_url)
        .placeholder("https://example.com")
        .on_edit(|ui: &mut Ui| &mut ui.test_url)
        .width(None)
        .build(k)
        .key("test-url");
    let link = ui.test_url.text.trim();
    let result = (!link.is_empty()).then(|| describe(&ui.editor.config, ui, link));
    let mut section = col()
        .key("test-section")
        .w_full()
        .gap(METRICS.label_gap)
        .px(METRICS.row_px)
        .child(text("Test a URL").key("label").font(k.ty.small_medium).color(p.muted()))
        .child(field);
    section = section.child(match result {
        Some((line, ok)) => text(line)
            .key("test-result")
            .font(DESCRIPTION)
            .color(if ok { p.text() } else { p.danger() })
            .wrap()
            .w_full(),
        None => text("Preview the matching rule and destination without opening the link.")
            .key("test-result")
            .font(DESCRIPTION)
            .color(p.muted()),
    });
    section
}

fn describe(config: &Config, ui: &Ui, link: &str) -> (String, bool) {
    if !(switchboard_core::url::is_web(link) || switchboard_core::url::is_local_file(link)) {
        return ("Enter a complete link, such as https://example.com/page.".into(), false);
    }
    let decision = router::decide(config, link);
    let d = &decision.destination;
    let target = format!(
        "{} · {}",
        ui.editor.browser_name(&d.browser),
        ui.editor.profile_name(&d.browser, &d.profile)
    );
    match decision.rule {
        Some(i) => {
            let r = &config.rules[i];
            (format!("Rule {} ({} {}) → {target}", i + 1, r.condition.as_str(), r.value), true)
        }
        None => (format!("No rule matches → the default, {target}"), true),
    }
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
    // The sheet's menus anchor to fields inside the sheet, so they mount after it (below).
    let mut menus = Vec::new();
    let browser = select(p, Open::DraftBrowser, &browser_label, ui.open, browsers, &mut menus);

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
        select(p, Open::DraftProfile, &e.profile_name(&target, &draft.profile), ui.open, choices, &mut menus);

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
    layer.extend(menus);
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
