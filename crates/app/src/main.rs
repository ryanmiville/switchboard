//! The Switchboard app binary.
//!
//! - Headless runs (`--snap`, `--tree`, `--script`, `--list-scenes`) use the fixture state only.
//! - Linux: `switchboard-rs-app <link>` (the browser desktop entry's `%u`) routes the link and exits
//!   without a window, unless it fails; with no link it opens Settings.
//! - macOS: links arrive through `App::on_open_url`. A launch that only delivers links quits
//!   shortly after the latest one.

use std::time::SystemTime;

use switchboard_app::editor::Editor;
use switchboard_app::ui::{Failure, Ui};
use switchboard_app::{platform, routing, spec};
use switchboard_core::history::HistoryStore;
use switchboard_core::store::ConfigStore;
use switchboard_core::time::Timestamp;
use switchboard_core::{Env, url};

fn main() {
    if rune::is_headless() {
        rune::run(spec());
        return;
    }
    let (home, env) = Env::from_process();
    let Some(home) = home else {
        eprintln!("switchboard-rs-app: $HOME isn't set.");
        std::process::exit(1);
    };
    let links: Vec<String> =
        std::env::args().skip(1).filter(|a| url::is_web(a) || url::is_local_file(a)).collect();
    let open_editor = move || {
        Editor::open(
            home.clone(),
            ConfigStore::new(home.config_file()),
            HistoryStore::new(home.history_file()),
            Box::new(platform::browsers(&home, &env)),
        )
    };

    // Linux hands each link to a new process. Route it from the file and exit, unless it fails.
    let mut failure = None;
    if !cfg!(target_os = "macos") && !links.is_empty() {
        let editor = open_editor();
        for link in &links {
            if let Err(reason) = open_link(&editor, link) {
                failure = Some(Failure { url: link.clone(), reason });
            }
        }
        if failure.is_none() {
            return;
        }
    }

    rune::prewarm_gpu();
    let app = rune::App::new(spec())
        .init(move || {
            let mut ui = Ui::new(open_editor());
            ui.failure = failure;
            ui.session.finish_launching(false);
            ui
        })
        .keep_running()
        .on_close(|ui: &mut Ui, _| {
            ui.editor.flush();
        })
        .on_open_url(|ui: &mut Ui, link: &str, tx| ui.receive_link(link, now(), tx))
        .on_reopen(|ui: &mut Ui, _visible, _| {
            ui.session.stay_resident();
            false
        });
    #[cfg(target_os = "macos")]
    let app = app.accessory();
    app.run();
}

fn now() -> Timestamp {
    #[expect(clippy::disallowed_methods, reason = "the binary reads the clock and passes it in")]
    Timestamp::from_system(SystemTime::now())
}

fn open_link(editor: &Editor, link: &str) -> Result<(), String> {
    if let Some(error) = &editor.load_error {
        return Err(error.clone());
    }
    routing::open(link, &editor.config, editor.browsers.as_ref(), &editor.history, now())
}
