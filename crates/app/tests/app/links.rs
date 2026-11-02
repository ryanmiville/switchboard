//! Links the system hands the app, opened through fixture browsers that record their arguments.

use switchboard_core::platform::recorded_launches;
use switchboard_core::time::Timestamp;

use super::support::{frames, runtime};

fn launches(rt: &rune::Runtime<switchboard_app::ui::Ui>, count: usize) -> Vec<Vec<String>> {
    let log = rt.state.editor.home.join("launches.log");
    for _ in 0..200 {
        let found = recorded_launches(&log);
        if found.len() >= count {
            return found;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    recorded_launches(&log)
}

#[test]
fn a_link_opens_in_the_matching_rules_browser_and_profile_and_is_recorded() {
    let mut rt = runtime("general");
    rt.update(|ui, tx| ui.receive_link("https://github.com/acme/api?x=1", Timestamp(1_000), tx));
    assert_eq!(
        launches(&rt, 1),
        [vec!["--profile-directory=Profile 1".to_owned(), "https://github.com/acme/api?x=1".to_owned()]]
    );
    let entries = rt.state.editor.history.entries().unwrap();
    assert_eq!(entries[0].rule.as_ref().unwrap().index, 1);
    assert_eq!(entries[0].profile_name.as_deref(), Some("Work"));
    assert!(rt.state.failure.is_none());
}

#[test]
fn pending_edits_are_saved_before_a_link_is_routed() {
    let mut rt = runtime("general");
    rt.update(|ui, _| ui.editor.edit(|c| c.rules.clear()));
    rt.update(|ui, tx| ui.receive_link("https://github.com/", Timestamp(1_000), tx));
    assert_eq!(
        launches(&rt, 1)[0][0],
        "--profile-directory=Default",
        "the default, since the rules were removed"
    );
    assert!(!rt.state.editor.has_unsaved_changes());
}

#[test]
fn a_link_that_cant_open_shows_a_recovery_notice_and_opens_nothing_else() {
    let mut rt = runtime("missing-profile");
    rt.update(|ui, tx| ui.receive_link("https://github.com/", Timestamp(1_000), tx));
    frames(&mut rt, 2);
    let failure = rt.state.failure.clone().expect("a failure notice");
    assert_eq!(failure.url, "https://github.com/");
    std::thread::sleep(std::time::Duration::from_millis(50));
    assert!(launches(&rt, 0).is_empty(), "no other browser or profile is guessed");
    assert!(rt.state.session.is_resident(), "a failure keeps the app open");
    assert!(rt.elements().iter().any(|e| e.key.as_deref() == Some("copy-link")));
}
