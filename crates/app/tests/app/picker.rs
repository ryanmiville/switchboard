//! The Quick Switch panel, over fixture browsers whose programs record their launches. Its link
//! is set directly: tests never summon it, which would read a real browser's tab.

use rune::{Env, Key, KeyEvent, Mods, Runtime};
use switchboard_app::picker::Picker;
use switchboard_app::{fixture, picker_spec};
use switchboard_core::history::Source;
use switchboard_core::platform::recorded_launches;

fn runtime(scene: &str) -> Runtime<Picker> {
    let state = rune::tooling::initial_state(&picker_spec(), Some(scene));
    let mut rt = Runtime::new(state, switchboard_app::ui::picker::view, (460.0, 460.0), Env::new(false, 1.0));
    rt.on_key = Some(|p, ev, tx| p.on_key(ev, tx));
    for _ in 0..20 {
        rt.frame(1.0 / 60.0);
    }
    rt
}

fn launches(rt: &Runtime<Picker>, count: usize) -> Vec<Vec<String>> {
    let log = rt.state.fixture.as_ref().unwrap().path().join("launches.log");
    for _ in 0..200 {
        if recorded_launches(&log).len() >= count {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    recorded_launches(&log)
}

fn labels(rt: &Runtime<Picker>) -> Vec<String> {
    rt.state.shown().iter().map(|c| c.label()).collect()
}

#[test]
fn favorites_come_first_with_their_saved_names() {
    let rt = runtime("picker");
    let shown = labels(&rt);
    assert_eq!(shown[0], "Helium · Ryan");
    assert!(rt.state.shown()[0].favorite);
    assert_eq!(shown.len(), 5, "{shown:?}");
}

#[test]
fn hidden_destinations_are_left_out_and_an_empty_list_says_so() {
    let mut rt = runtime("picker-empty");
    assert!(rt.state.shown().is_empty());
    assert!(rt.elements().iter().any(|e| e.key.as_deref() == Some("empty")));
    rt.update(|p, _| {
        let keep = p.all[2].destination.clone();
        p.settings.destinations = Some(vec![keep]);
    });
    assert_eq!(rt.state.shown().len(), 1);
}

#[test]
fn opening_a_destination_launches_that_profile_with_the_link_and_records_it_as_a_pick() {
    let mut rt = runtime("picker");
    let target = rt.state.shown()[3].destination.clone();
    rt.update(|p, tx| p.open(3, tx));
    assert_eq!(
        launches(&rt, 1),
        [vec![
            format!("--profile-directory={}", target.profile),
            "https://github.com/acme/api/pull/12".to_owned()
        ]]
    );
    assert_eq!(rt.state.opened.as_ref().map(|o| &o.1), Some(&target));
    let entries = rt.state.history.entries().unwrap();
    assert_eq!(entries[0].source, Source::Picker);
    assert_eq!(entries[0].rule, None, "a manual pick ignores the rules");
}

#[test]
fn a_favorite_that_is_gone_shows_why_and_opens_nothing() {
    let mut rt = runtime("picker-unavailable-favorite");
    let index = rt.state.shown().iter().position(|c| c.profile_name == "Old work").unwrap();
    assert!(rt.state.shown()[index].error.is_some());
    rt.update(move |p, tx| p.open(index, tx));
    assert!(rt.state.error.is_some());
    std::thread::sleep(std::time::Duration::from_millis(50));
    assert!(launches(&rt, 0).is_empty(), "no similar profile is guessed");
}

#[test]
fn a_link_that_isnt_a_web_link_is_refused() {
    let mut rt = runtime("picker");
    rt.update(|p, tx| {
        p.link = rune::TextEdit::new("github.com/acme");
        p.open(0, tx);
    });
    assert!(rt.state.error.as_deref().unwrap().contains("complete HTTP or HTTPS link"));
    assert!(rt.state.opened.is_none());
}

#[test]
fn command_one_opens_the_first_favorite_and_arrows_move_the_selection() {
    let mut rt = runtime("picker");
    rt.key(KeyEvent { key: Key::Down, mods: Mods::default() });
    rt.frame(1.0 / 60.0);
    assert_eq!(rt.state.selected, 1);
    rt.key(KeyEvent { key: Key::Command('1'), mods: Mods { cmd: true, ..Mods::default() } });
    rt.frame(1.0 / 60.0);
    assert_eq!(launches(&rt, 1)[0][0], "--profile-directory=Default");
    assert_eq!(rt.state.opened.as_ref().unwrap().1.browser, rt.state.shown()[0].destination.browser);
}

#[test]
fn starring_a_destination_saves_it_as_a_favorite_in_the_config() {
    let mut rt = runtime("picker");
    rt.update(|p, _| p.toggle_favorite(3));
    let saved = rt.state.store.load().unwrap().config.picker.unwrap();
    assert_eq!(saved.favorites.len(), 2);
    assert!(rt.state.shown()[1].favorite, "favorites move to the top");
    rt.update(|p, _| p.toggle_favorite(0));
    assert_eq!(rt.state.store.load().unwrap().config.picker.unwrap().favorites.len(), 1);
}

#[test]
fn the_fixture_picker_never_uses_the_real_home() {
    let p = fixture::picker();
    let home = p.fixture.as_ref().unwrap().path().to_path_buf();
    assert!(p.store.path.starts_with(&home) && p.history.path.starts_with(&home));
}
