use rune::{Key, KeyEvent, Mods};
use switchboard_app::ui::Pane;

use super::support::{frames, runtime, saved, shows, tap};

#[test]
fn switching_panes_is_instant() {
    let mut rt = runtime("general");
    tap(&mut rt, "nav-routing");
    assert_eq!(rt.state.pane, Pane::Routing);
    rt.frame(1.0 / 60.0);
    for e in rt.elements() {
        assert!(!e.exiting, "{} is still leaving", e.path);
        assert!(!e.moving, "{} is still moving", e.path);
    }
    assert!(shows(&rt, "First match wins"));
}

#[test]
fn a_toggle_saves_after_the_autosave_delay_and_not_before() {
    let mut rt = runtime("general");
    tap(&mut rt, "history-toggle");
    assert_eq!(saved(&rt).get("history"), None, "nothing is written straight away");
    assert!(rt.state.editor.has_unsaved_changes());
    frames(&mut rt, 45);
    assert_eq!(saved(&rt)["history"], serde_json::json!({ "enabled": false }));
    assert!(!rt.state.editor.has_unsaved_changes());
}

#[test]
fn choosing_a_default_profile_from_the_menu_saves_its_directory() {
    let mut rt = runtime("general");
    tap(&mut rt, "default-profile-field-trigger");
    assert!(shows(&rt, "Work (Profile 1)"), "the menu lists names with their directories");
    rt.update(|ui, _| ui.editor.select_default_profile("Profile 1"));
    rt.update(|ui, _| {
        ui.editor.flush();
    });
    assert_eq!(saved(&rt)["defaultProfile"], "Profile 1");
}

#[test]
fn adding_a_rule_through_the_sheet_saves_it_with_its_own_browser() {
    let mut rt = runtime("routing");
    tap(&mut rt, "add-rule");
    assert!(rt.state.draft.is_some());
    let chrome =
        rt.state.editor.installed.iter().find(|b| b.name == "Google Chrome").unwrap().locator.clone();
    rt.update(move |ui, _| {
        let draft = ui.draft.as_mut().unwrap();
        draft.value = rune::TextEdit::new("example.org");
        draft.select_browser(Some(chrome.clone()), "");
        draft.profile = "Profile 3".into();
    });
    frames(&mut rt, 2);
    tap(&mut rt, "draft-done");
    assert!(rt.state.draft.is_none(), "{:?}", rt.state.draft.as_ref().and_then(|d| d.error.clone()));
    rt.update(|ui, _| {
        ui.editor.flush();
    });
    let rules = saved(&rt)["rules"].clone();
    assert_eq!(rules[4]["value"], "example.org");
    assert_eq!(rules[4]["profile"], "Profile 3");
}

#[test]
fn done_refuses_a_rule_without_a_profile_or_with_a_path_as_a_domain() {
    let mut rt = runtime("rule-new");
    rt.update(|ui, _| ui.draft.as_mut().unwrap().value = rune::TextEdit::new("github.com/acme"));
    tap(&mut rt, "draft-done");
    assert!(shows(&rt, "isn't a domain"));
    rt.update(|ui, _| ui.draft.as_mut().unwrap().value = rune::TextEdit::new("github.com"));
    tap(&mut rt, "draft-done");
    assert!(shows(&rt, "Choose a profile."));
    assert_eq!(rt.state.editor.config.rules.len(), 4, "nothing was added");
}

#[test]
fn changing_a_drafts_browser_asks_for_a_new_profile() {
    let rt = runtime("rule-edit");
    let mut draft = switchboard_app::ui::Draft::editing(&rt.state.editor.config.rules[1]);
    let default = rt.state.editor.config.browser.clone();
    assert_eq!(draft.profile, "Profile 2");
    draft.select_browser(None, &default);
    assert_eq!(draft.profile, "", "the same directory in another browser can be a different person");
}

#[test]
fn escape_closes_the_innermost_open_thing() {
    let mut rt = runtime("rule-new");
    tap(&mut rt, "draft-browser-field-trigger");
    assert!(rt.state.open.is_some());
    let esc = KeyEvent { key: Key::Escape, mods: Mods::default() };
    rt.key(esc.clone());
    frames(&mut rt, 2);
    assert!(rt.state.open.is_none());
    assert!(rt.state.draft.is_some());
    rt.key(esc);
    frames(&mut rt, 2);
    assert!(rt.state.draft.is_none());
}

#[test]
fn a_recorded_shortcut_is_saved_and_a_refused_one_is_not() {
    let mut rt = runtime("quick-switch");
    let shortcut: rune::Shortcut = "ctrl+shift+k".parse().unwrap();
    rt.update(move |ui, _| ui.record_shortcut(Some(&shortcut)).unwrap());
    rt.update(|ui, _| {
        ui.editor.flush();
    });
    assert_eq!(saved(&rt)["picker"]["shortcut"], "ctrl+shift+k");

    rt.update(|ui, _| ui.register_shortcut = Some(Box::new(|_| Err(rune::ShortcutError::Conflict))));
    let other: rune::Shortcut = "ctrl+alt+j".parse().unwrap();
    rt.update(move |ui, _| assert!(ui.record_shortcut(Some(&other)).is_err()));
    rt.update(|ui, _| {
        ui.editor.flush();
    });
    assert_eq!(saved(&rt)["picker"]["shortcut"], "ctrl+shift+k", "a refused chord is never saved");
}

#[test]
fn a_menu_inside_the_rule_sheet_opens_under_its_field() {
    let rt = runtime("rule-browser-menu");
    let elements = rt.elements();
    let rect =
        |key: &str| elements.iter().find(|e| e.key.as_deref() == Some(key) && !e.exiting).map(|e| e.rect);
    let [fx, fy, fw, fh] = rect("draft-browser-field-trigger").expect("the field");
    let [mx, my, mw, _] = rect("draft-browser-menu").expect("the menu");
    // The menu hangs from the field's bottom-right corner (it is wider than the field).
    assert!(
        ((mx + mw) - (fx + fw)).abs() <= 2.0,
        "the menu ends where its field does ({} vs {})",
        mx + mw,
        fx + fw
    );
    assert!(
        my >= fy + fh && my <= fy + fh + 12.0,
        "the menu opens just below its field ({my} vs {})",
        fy + fh
    );
}

fn row(rt: &rune::Runtime<switchboard_app::ui::Ui>, index: usize) -> String {
    format!("rule-{}", switchboard_app::ui::routing::rule_key(&rt.state.editor.config.rules[index]))
}

fn values(rt: &rune::Runtime<switchboard_app::ui::Ui>) -> Vec<String> {
    rt.state.editor.config.rules.iter().map(|r| r.value.clone()).collect()
}

#[test]
fn clicking_a_row_selects_it_and_minus_removes_it() {
    let mut rt = runtime("routing");
    let key = row(&rt, 1);
    tap(&mut rt, &key);
    assert_eq!(rt.state.selected_index(), Some(1));
    tap(&mut rt, "remove-rule");
    assert_eq!(values(&rt), ["github.com", "docs.github.com", "https://example.com/login"]);
    assert_eq!(rt.state.selected_index(), Some(1), "the next rule is selected");
}

#[test]
fn double_clicking_a_row_opens_its_editor() {
    let mut rt = runtime("routing");
    let key = row(&rt, 2);
    let (x, y) = rt.find(&key).unwrap();
    rt.pointer_down(x, y);
    rt.pointer_up(x, y);
    rt.pointer_down(x, y);
    rt.pointer_up(x, y);
    frames(&mut rt, 2);
    let draft = rt.state.draft.as_ref().expect("the rule sheet");
    assert!(!draft.is_new);
    assert_eq!(draft.value.text, "docs.github.com");
}

#[test]
fn dragging_a_row_down_two_places_drops_it_there() {
    use switchboard_app::ui::routing::ROW_H;
    let mut rt = runtime("routing");
    let key = row(&rt, 0);
    let (x, y) = rt.find(&key).unwrap();
    rt.pointer_down(x, y);
    for step in 1..=10 {
        rt.pointer_move(x, y + step as f32 * 2.0 * ROW_H / 10.0);
        rt.frame(1.0 / 60.0);
    }
    assert_eq!(rt.state.drag.map(|d| d.to), Some(2), "it would land at the third place");
    assert_eq!(values(&rt)[0], "github.com", "nothing moves until the drop");
    rt.pointer_up(x, y + 2.0 * ROW_H);
    frames(&mut rt, 2);
    assert_eq!(values(&rt), ["acme", "docs.github.com", "github.com", "https://example.com/login"]);
    assert!(rt.state.drag.is_none());
}

#[test]
fn escape_during_a_drag_puts_the_row_back() {
    use switchboard_app::ui::routing::ROW_H;
    let mut rt = runtime("routing");
    let key = row(&rt, 3);
    let (x, y) = rt.find(&key).unwrap();
    rt.pointer_down(x, y);
    rt.pointer_move(x, y - 2.0 * ROW_H);
    rt.frame(1.0 / 60.0);
    assert!(rt.state.drag.is_some());
    rt.key(KeyEvent { key: Key::Escape, mods: Mods::default() });
    rt.pointer_up(x, y - 2.0 * ROW_H);
    frames(&mut rt, 2);
    assert_eq!(values(&rt)[3], "https://example.com/login");
}

#[test]
fn arrows_move_the_selection_return_edits_and_delete_removes() {
    let mut rt = runtime("routing");
    let key = |k| KeyEvent { key: k, mods: Mods::default() };
    rt.key(key(Key::Down));
    rt.key(key(Key::Down));
    frames(&mut rt, 1);
    assert_eq!(rt.state.selected_index(), Some(1));
    rt.key(key(Key::Enter));
    frames(&mut rt, 1);
    assert_eq!(rt.state.draft.as_ref().map(|d| d.value.text.clone()).as_deref(), Some("acme"));
    rt.key(key(Key::Escape));
    rt.key(key(Key::Backspace));
    frames(&mut rt, 1);
    assert_eq!(values(&rt), ["github.com", "docs.github.com", "https://example.com/login"]);
}

#[test]
fn testing_a_url_shows_the_rule_it_matches_without_opening_it() {
    let rt = runtime("routing-test");
    assert!(shows(&rt, "Rule 1 (domain github.com) → Helium · Work"), "{:?}", super::support::texts(&rt));
    assert!(
        std::fs::read_to_string(rt.state.editor.home.join("launches.log")).is_err(),
        "nothing was opened"
    );
}

#[test]
fn the_sidebar_edge_is_brighter_while_the_window_has_focus() {
    let mut rt = runtime("general");
    let edge = |rt: &rune::Runtime<switchboard_app::ui::Ui>| rt.state.focused;
    assert!(edge(&rt));
    rt.window_focus(false);
    frames(&mut rt, 2);
    assert!(!edge(&rt), "losing focus dims the edge");
    rt.window_focus(true);
    frames(&mut rt, 2);
    assert!(edge(&rt));
}
