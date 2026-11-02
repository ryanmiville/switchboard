//! The Switchboard app binary.
//!
//! - Headless runs (`--snap`, `--tree`, `--script`, `--list-scenes`) use the fixture state only.
//! - macOS: the app starts without a window, as a menu-bar app. Links arrive through
//!   `App::on_open_url`; a launch that only delivers links quits shortly after the latest one and
//!   never shows the menu-bar icon. Settings opens from the icon, or by opening the app again.
//! - Linux: `switchboard-rs-app <link>` (the browser desktop entry's `%u`) routes the link and
//!   exits without a window, unless it fails. With no link it opens Settings and a tray icon.

use std::cell::{OnceCell, RefCell};
use std::sync::{Arc, Mutex};
use std::time::SystemTime;

use switchboard_app::editor::Editor;
use switchboard_app::picker::Picker;
use switchboard_app::ui::{Failure, Ui};
use switchboard_app::{picker_spec, platform, routing, spec, watch};
use switchboard_core::history::HistoryStore;
use switchboard_core::platform::{CurrentTab, MenuAction, MenuBar};
use switchboard_core::store::ConfigStore;
use switchboard_core::time::Timestamp;
use switchboard_core::{Env, url};

thread_local! {
    static WINDOW: OnceCell<rune::AppHandle<Ui>> = const { OnceCell::new() };
    static PICKER: OnceCell<rune::AppHandle<Picker>> = const { OnceCell::new() };
    static MENU_BAR: RefCell<Option<platform::PlatformMenuBar>> = const { RefCell::new(None) };
}

fn main() {
    if rune::is_headless() {
        // Fixture state only: `--window picker` renders the Quick Switch panel's scenes.
        rune::run_windows(|_| -> Vec<rune::AnyWindowSpec> {
            vec![
                rune::WindowSpec::new("settings", spec()).into(),
                rune::WindowSpec::new("picker", picker_spec()).into(),
            ]
        });
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
    let picker_env = env.clone();
    let config_path = home.config_file();
    let picker_home = home.clone();
    let shortcut = ConfigStore::new(home.config_file())
        .load()
        .ok()
        .and_then(|s| s.config.picker)
        .unwrap_or_default()
        .shortcut;
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

    let tab: Arc<dyn CurrentTab> = Arc::new(platform::PlatformCurrentTab);

    let settings = rune::App::new(spec());
    let picker = rune::App::new(picker_spec()).windowless();
    let (settings_handle, picker_handle) = (settings.handle(), picker.handle());
    let picker = {
        let (settings_handle, me) = (settings_handle.clone(), picker_handle.clone());
        picker
            .init(move || {
                let home = picker_home;
                let mut p = Picker::new(
                    ConfigStore::new(home.config_file()),
                    HistoryStore::new(home.history_file()),
                    Box::new(platform::browsers(&home, &picker_env)),
                    tab,
                    now,
                );
                p.settings_window = Some(settings_handle);
                p.me = Some(me);
                p
            })
            // The panel goes when the person goes elsewhere, as the Swift panel did.
            .on_focus(|_, focused, tx| {
                if !focused {
                    tx.close_window();
                }
            })
    };
    let registered: Arc<Mutex<Option<rune::ShortcutId>>> = Arc::default();
    let settings = settings
        .init({
            let (picker_handle, registered) = (picker_handle.clone(), registered.clone());
            move || {
                let mut ui = Ui::new(open_editor());
                ui.editor.initialize_picker();
                ui.failure = failure;
                ui.login_item = Some(Box::new(login_item));
                ui.register_shortcut =
                    Some(Box::new(move |shortcut| register_shortcut(&picker_handle, &registered, shortcut)));
                ui
            }
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
    let settings = settings.windowless();
    #[cfg(not(target_os = "macos"))]
    rune::prewarm_gpu();
    let (picker_for_shortcut, registered_at_launch) = (picker_handle.clone(), registered.clone());
    WINDOW.with(|w| w.set(settings_handle.clone()).ok());
    PICKER.with(|w| w.set(picker_handle.clone()).ok());
    // The loop's first turn: links that launched the app have arrived by now, so a launch with no
    // link is a resident one and gets its icon. `false`: nothing on screen changes.
    {
        let (picker_handle, settings_handle) = (picker_handle.clone(), settings_handle.clone());
        watch::watch(config_path, move || {
            settings_handle.update(|ui, _| {
                ui.editor.check_external();
            });
            picker_handle.update(|p, _| p.refresh());
        });
    }
    settings_handle.update_if(move |ui, _| {
        // The Quick Switch shortcut, from the saved config.
        let registered = shortcut
            .as_str()
            .parse::<rune::Shortcut>()
            .and_then(|s| register_shortcut(&picker_for_shortcut, &registered_at_launch, &s));
        if let Err(error) = registered {
            eprintln!(
                "switchboard-rs-app: the Quick Switch shortcut {} couldn't be registered: {error}",
                shortcut.as_str()
            );
            ui.recorder.mark_unregistered();
        }
        ui.session.finish_launching(false);
        if ui.session.is_resident() {
            show_menu_bar();
        }
        false
    });
    let options = rune::RunOptions { accessory: cfg!(target_os = "macos") };
    rune::run_windows_with(options, move |_| -> Vec<rune::AnyWindowSpec> {
        vec![
            rune::WindowSpec::from_app("settings", settings).into(),
            rune::WindowSpec::from_app("picker", picker)
                .configured_options(rune::WindowOptions::launcher_panel())
                .into(),
        ]
    });
}

/// Registers `shortcut` to summon the picker, then releases the one it replaces, so a refused
/// chord leaves the old shortcut working.
fn register_shortcut(
    picker: &rune::AppHandle<Picker>,
    registered: &Mutex<Option<rune::ShortcutId>>,
    shortcut: &rune::Shortcut,
) -> Result<(), rune::ShortcutError> {
    let id = picker.register_shortcut(shortcut.clone(), |p, tx| p.summon(tx))?;
    let Ok(mut current) = registered.lock() else { return Ok(()) };
    if let Some(old) = current.replace(id) {
        picker.unregister_shortcut(old).ok();
    }
    Ok(())
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
            MenuAction::QuickSwitch => {
                if let Some(picker) = PICKER.with(|p| p.get().cloned()) {
                    picker.update(|p, tx| p.summon(tx));
                }
            }
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
