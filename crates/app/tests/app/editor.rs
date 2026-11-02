//! The editor against the real store: what happens when the CLI writes the file too.

use super::support::runtime;

#[test]
fn a_file_changed_elsewhere_reloads_when_nothing_is_pending() {
    let mut rt = runtime("general");
    let path = rt.state.editor.store.path.clone();
    let mut config = rt.state.editor.config.clone();
    config.default_profile = "Profile 1".into();
    std::fs::write(&path, config.encode()).unwrap();
    rt.update(|ui, _| {
        ui.editor.check_external();
    });
    assert_eq!(rt.state.editor.config.default_profile, "Profile 1");
    assert!(!rt.state.editor.conflict);
}

#[test]
fn a_file_changed_elsewhere_with_pending_edits_is_a_conflict_that_keeps_both() {
    let mut rt = runtime("general");
    let path = rt.state.editor.store.path.clone();
    rt.update(|ui, _| ui.editor.select_default_profile("Profile 1"));
    let theirs = b"{\"browser\":\"\",\"defaultProfile\":\"Default\"}\n";
    std::fs::write(&path, theirs).unwrap();
    rt.update(|ui, _| {
        ui.editor.check_external();
        ui.editor.flush();
    });
    assert!(rt.state.editor.conflict);
    assert_eq!(std::fs::read(&path).unwrap(), theirs, "their file is never overwritten silently");
    assert_eq!(rt.state.editor.config.default_profile, "Profile 1", "and my edit is kept");

    rt.update(|ui, _| {
        ui.editor.keep_mine();
    });
    assert!(!rt.state.editor.conflict);
    assert!(String::from_utf8(std::fs::read(&path).unwrap()).unwrap().contains("Profile 1"));
}

#[test]
fn an_unreadable_file_is_never_replaced_and_edits_are_refused() {
    let mut rt = runtime("load-error");
    let path = rt.state.editor.store.path.clone();
    rt.update(|ui, _| {
        ui.editor.select_default_profile("Profile 1");
        ui.editor.flush();
    });
    assert_eq!(std::fs::read(&path).unwrap(), b"{\"browser\": ");
    assert!(rt.state.editor.load_error.is_some());
}

#[test]
fn a_new_default_browser_clears_the_profiles_chosen_in_the_old_one() {
    let mut rt = runtime("general");
    let chrome =
        rt.state.editor.installed.iter().find(|b| b.name == "Google Chrome").unwrap().locator.clone();
    rt.update(move |ui, _| ui.editor.select_default_browser(&chrome));
    let c = &rt.state.editor.config;
    assert_eq!(c.default_profile, "");
    assert_eq!(c.rules[0].profile, "", "the rule inheriting the default browser needs a new profile");
    assert_eq!(c.rules[1].profile, "Profile 2", "a rule with its own browser keeps its profile");
    assert!(!rt.state.editor.flush(), "saving waits for a profile");
}

#[test]
fn the_watcher_notices_a_save_made_elsewhere() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("config.json");
    std::fs::write(&path, b"{}").unwrap();
    let (tx, rx) = std::sync::mpsc::channel();
    switchboard_app::watch::watch(path.clone(), move || {
        tx.send(()).ok();
    });
    // An atomic replace, as every save does.
    let temp = dir.path().join("config.json.tmp");
    std::fs::write(&temp, b"{\"browser\":\"x\"}").unwrap();
    std::fs::rename(&temp, &path).unwrap();
    assert!(rx.recv_timeout(std::time::Duration::from_secs(3)).is_ok());
}

#[test]
fn a_config_without_picker_settings_starts_with_the_owners_favorites_once() {
    let mut rt = runtime("general");
    rt.update(|ui, _| {
        ui.editor.edit(|c| c.picker = None);
        ui.editor.initialize_picker();
    });
    let favorites = rt.state.editor.config.picker.clone().unwrap().favorites;
    // The fixture has Helium's "Ryan" but no Chrome profile named "horizon3.ai".
    assert_eq!(favorites.len(), 1);
    assert_eq!((favorites[0].profile.as_str(), favorites[0].name.as_str()), ("Default", "Ryan"));
    rt.update(|ui, _| {
        ui.editor.edit(|c| c.picker.as_mut().unwrap().favorites.clear());
        ui.editor.initialize_picker();
    });
    assert!(
        rt.state.editor.config.picker.as_ref().unwrap().favorites.is_empty(),
        "an existing section is left alone"
    );
}
