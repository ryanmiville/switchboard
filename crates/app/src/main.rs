//! The Switchboard app binary.
//!
//! - Headless runs (`--snap`, `--tree`, `--script`, `--list-scenes`) use the fixture state only.
//! - macOS: the app starts without a window, as a menu-bar app. Links arrive through
//!   `App::on_open_url`; a launch that only delivers links quits shortly after the latest one and
//!   never shows the menu-bar icon. Settings opens from the icon, or by opening the app again.
//! - Linux: `switchboard-rs-app <link>` (the browser desktop entry's `%u`) routes the link and
//!   exits without a window, unless it fails. With no link it opens Settings and a tray icon.

use std::cell::{OnceCell, RefCell};
use std::sync::Mutex;
use std::time::SystemTime;

use switchboard_app::editor::Editor;
use switchboard_app::ui::{Failure, Ui};
use switchboard_app::{platform, routing, spec};
use switchboard_core::history::HistoryStore;
use switchboard_core::platform::{MenuAction, MenuBar};
use switchboard_core::store::ConfigStore;
use switchboard_core::time::Timestamp;
use switchboard_core::{Env, url};

thread_local! {
    static WINDOW: OnceCell<rune::AppHandle<Ui>> = const { OnceCell::new() };
    static MENU_BAR: RefCell<Option<platform::PlatformMenuBar>> = const { RefCell::new(None) };
}

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
    let program = std::env::current_exe().unwrap_or_default();
    let login_item = platform::login_item(&home, program);
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

    let app = rune::App::new(spec())
        .init(move || {
            let mut ui = Ui::new(open_editor());
            ui.failure = failure;
            ui.login_item = Some(Box::new(login_item));
            ui
        })
        .keep_running()
        .on_close(|ui: &mut Ui, tx| {
            ui.editor.flush();
            // Without a menu-bar or tray icon there would be no way back to a closed window.
            if MENU_BAR.with(|m| m.borrow().is_none()) {
                tx.quit();
            }
        })
        .on_open_url(|ui: &mut Ui, link: &str, tx| {
            ui.receive_link(link, now(), tx);
            if ui.failure.is_some() {
                show_menu_bar();
                show_window();
            }
        })
        .on_reopen(|ui: &mut Ui, _visible, _| {
            // Opening the app again (Finder, Spotlight, the Dock) means the person wants it.
            ui.session.stay_resident();
            show_menu_bar();
            show_window();
            true
        });
    #[cfg(target_os = "macos")]
    let app = app.accessory().windowless();
    #[cfg(not(target_os = "macos"))]
    rune::prewarm_gpu();
    let handle = app.handle();
    WINDOW.with(|w| w.set(handle.clone()).ok());
    // The loop's first turn: links that launched the app have arrived by now, so a launch with no
    // link is a resident one and gets its icon. `false`: nothing on screen changes.
    handle.update_if(|ui, _| {
        ui.session.finish_launching(false);
        if ui.session.is_resident() {
            show_menu_bar();
        }
        false
    });
    app.run();
}

/// Installs the menu-bar (macOS) or tray (Linux) icon once. On macOS, if it can't be installed,
/// the window opens instead, since there would be no other way to reach Settings.
fn show_menu_bar() {
    if MENU_BAR.with(|m| m.borrow().is_some()) {
        return;
    }
    let Some(handle) = WINDOW.with(|w| w.get().cloned()) else { return };
    let handle = Mutex::new(handle);
    let installed = platform::PlatformMenuBar::install(Box::new(move |action| {
        let Ok(handle) = handle.lock() else { return };
        match action {
            MenuAction::OpenSettings => {
                handle.update(|ui, _| ui.session.stay_resident());
                platform::bring_to_front();
                handle.open();
            }
            MenuAction::Quit => handle.update(|ui, tx| {
                ui.editor.flush();
                tx.quit();
            }),
        }
    }));
    match installed {
        Ok(bar) => MENU_BAR.with(|m| *m.borrow_mut() = Some(bar)),
        Err(error) => {
            eprintln!("switchboard-rs-app: the menu-bar icon couldn't be shown: {error}");
            show_window();
        }
    }
}

fn show_window() {
    if let Some(handle) = WINDOW.with(|w| w.get().cloned()) {
        platform::bring_to_front();
        handle.open();
    }
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
