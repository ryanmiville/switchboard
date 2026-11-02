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
    assert!(shows(&rt, "Rules are checked in order"));
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
fn moving_a_rule_down_swaps_it_with_the_next() {
    let mut rt = runtime("routing");
    tap(&mut rt, "rule-0/actions/down");
    rt.update(|ui, _| {
        ui.editor.flush();
    });
    let rules = saved(&rt)["rules"].clone();
    assert_eq!(rules[0]["value"], "acme");
    assert_eq!(rules[1]["value"], "github.com");
}
