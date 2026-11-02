//! Every scene builds, settles, and stops asking for frames.

use switchboard_app::scenes::SCENES;

use super::support::{frames, runtime};

#[test]
fn every_scene_settles_and_nothing_keeps_moving() {
    for (name, _) in SCENES {
        let mut rt = runtime(name);
        frames(&mut rt, 120);
        let moving: Vec<String> = rt.elements().into_iter().filter(|e| e.moving).map(|e| e.path).collect();
        assert!(moving.is_empty(), "scene {name}: still moving after 2 s: {moving:?}");
    }
}

#[test]
fn scenes_never_touch_the_real_home() {
    for (name, _) in SCENES {
        let rt = runtime(name);
        let home = rt.state.editor.home.path().to_path_buf();
        assert!(
            rt.state.fixture.as_ref().is_some_and(|d| d.path() == home),
            "scene {name} uses {}",
            home.display()
        );
        assert!(rt.state.editor.store.path.starts_with(&home));
        assert!(rt.state.editor.history.path.starts_with(&home));
    }
}
