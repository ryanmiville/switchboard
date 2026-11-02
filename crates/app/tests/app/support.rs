use rune::{Env, Runtime};
use switchboard_app::ui::{Ui, view};
use switchboard_app::{SIZE, spec};

/// A runtime started from `scene`, settled.
pub fn runtime(scene: &str) -> Runtime<Ui> {
    let state = rune::tooling::initial_state(&spec(), Some(scene));
    runtime_for(state)
}

pub fn runtime_for(state: Ui) -> Runtime<Ui> {
    let mut rt = Runtime::new(state, view, SIZE, Env::new(false, 1.0));
    rt.poll = Some(|ui, now, tx| ui.poll(now, tx));
    rt.on_key = Some(|ui, ev, tx| ui.on_key(ev, tx));
    frames(&mut rt, 30);
    rt
}

pub fn frames(rt: &mut Runtime<Ui>, n: usize) {
    for _ in 0..n {
        rt.frame(1.0 / 60.0);
    }
}

#[track_caller]
pub fn tap(rt: &mut Runtime<Ui>, key: &str) {
    let (x, y) = rt.find(key).unwrap_or_else(|| panic!("no element {key}"));
    rt.pointer_down(x, y);
    rt.pointer_up(x, y);
    frames(rt, 2);
}

pub fn texts(rt: &Runtime<Ui>) -> Vec<String> {
    rt.elements().into_iter().filter(|e| !e.exiting).filter_map(|e| e.text).collect()
}

pub fn shows(rt: &Runtime<Ui>, needle: &str) -> bool {
    texts(rt).iter().any(|t| t.contains(needle))
}

/// The config file as JSON.
pub fn saved(rt: &Runtime<Ui>) -> serde_json::Value {
    serde_json::from_slice(&std::fs::read(&rt.state.editor.store.path).unwrap()).unwrap()
}
