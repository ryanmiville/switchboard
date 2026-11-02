//! Quick Switch: a panel that opens the focused browser's current page in another browser
//! profile, chosen by hand. It bypasses the routing rules on purpose.
//!
//! Summoned by the global shortcut: it remembers the app in front, reads that browser's current
//! tab on a worker thread (macOS asks for Automation permission the first time), and shows the
//! destinations the config allows, favorites first.

use std::sync::Arc;

use rune::{AppHandle, TextEdit, Tx};
use switchboard_core::history::{self, HistoryStore, Opened, Origin};
use switchboard_core::picker::{Favorite, PickerSettings};
use switchboard_core::platform::{BrowserInfo, CurrentTab, TabError};
use switchboard_core::store::ConfigStore;
use switchboard_core::time::Timestamp;
use switchboard_core::{Browsers, Config, Destination, launch, profiles, url};

use crate::ui::Ui;

/// One destination in the panel.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Choice {
    pub destination: Destination,
    pub browser_name: String,
    pub profile_name: String,
    pub favorite: bool,
    /// Why it can't be opened: the browser or profile is gone, or its profiles can't be read.
    pub error: Option<String>,
}

impl Choice {
    pub fn label(&self) -> String {
        format!("{} · {}", self.browser_name, self.profile_name)
    }
}

const UNAVAILABLE: &str =
    "This browser or profile is unavailable. Refresh, or hide it in Quick Switch settings.";

/// Every destination: favorites first in their saved order, then each installed browser's
/// profiles, then destinations the settings name that aren't installed (shown with an error,
/// never replaced by a similar one in another browser), then browsers whose profiles couldn't be
/// read.
pub fn choices(installed: &[BrowserInfo], settings: &PickerSettings) -> Vec<Choice> {
    let mut found: Vec<Choice> = Vec::new();
    let mut errors: Vec<(String, String)> = Vec::new();
    for browser in installed {
        match profiles::read(browser) {
            Ok(list) => found.extend(list.into_iter().map(|p| Choice {
                destination: Destination { browser: browser.locator.clone(), profile: p.directory },
                browser_name: browser.name.clone(),
                profile_name: p.name,
                favorite: false,
                error: None,
            })),
            Err(e) => errors.push((browser.locator.clone(), e.to_string())),
        }
    }
    let error_of = |locator: &str| errors.iter().find(|(l, _)| l == locator).map(|(_, e)| e.clone());
    let mut pinned: Vec<Choice> = Vec::new();
    for f in &settings.favorites {
        let d = f.destination();
        if pinned.iter().any(|c| c.destination == d) {
            continue;
        }
        let existing = found.iter().find(|c| c.destination == d);
        pinned.push(Choice {
            browser_name: installed
                .iter()
                .find(|b| b.locator == f.browser)
                .map_or_else(|| switchboard_core::platform::file_stem(&f.browser), |b| b.name.clone()),
            profile_name: f.name.clone(),
            favorite: true,
            error: existing.is_none().then(|| error_of(&f.browser).unwrap_or_else(|| UNAVAILABLE.into())),
            destination: d,
        });
    }
    found.retain(|c| !pinned.iter().any(|p| p.destination == c.destination));
    for d in settings.destinations.iter().flatten() {
        if !pinned.iter().chain(&found).any(|c| &c.destination == d) {
            found.push(Choice {
                destination: d.clone(),
                browser_name: switchboard_core::platform::file_stem(&d.browser),
                profile_name: d.profile.clone(),
                favorite: false,
                error: Some(error_of(&d.browser).unwrap_or_else(|| UNAVAILABLE.into())),
            });
        }
    }
    for (locator, error) in &errors {
        if !pinned.iter().chain(&found).any(|c| &c.destination.browser == locator) {
            found.push(Choice {
                destination: Destination { browser: locator.clone(), profile: String::new() },
                browser_name: switchboard_core::platform::file_stem(locator),
                profile_name: "Profiles unavailable".into(),
                favorite: false,
                error: Some(error.clone()),
            });
        }
    }
    pinned.extend(found);
    pinned
}

pub struct Picker {
    pub link: TextEdit,
    pub error: Option<String>,
    /// The error is a missing Automation permission, so the panel offers its settings.
    pub needs_permission: bool,
    /// Every destination, hidden ones included.
    pub all: Vec<Choice>,
    pub settings: PickerSettings,
    /// Index into [`Picker::shown`].
    pub selected: usize,
    pub config: Config,
    pub store: ConfigStore,
    pub history: HistoryStore,
    pub browsers: Box<dyn Browsers>,
    pub tab: Arc<dyn CurrentTab>,
    /// The settings window, to save favorites through its editor and to open it.
    pub settings_window: Option<AppHandle<Ui>>,
    /// This panel, so a worker can deliver the tab it read.
    pub me: Option<AppHandle<Picker>>,
    /// The last destination opened, for tests.
    pub opened: Option<(String, Destination)>,
    /// A wall-clock source, so tests can fix the time history records.
    pub clock: fn() -> Timestamp,
    pub fixture: Option<tempfile::TempDir>,
}

/// The panel's width, and the height of one destination row.
pub const WIDTH: f32 = 460.0;
pub const ROW_H: f32 = 52.0;

impl Picker {
    pub fn new(
        store: ConfigStore,
        history: HistoryStore,
        browsers: Box<dyn Browsers>,
        tab: Arc<dyn CurrentTab>,
        clock: fn() -> Timestamp,
    ) -> Picker {
        let mut picker = Picker {
            link: TextEdit::new(""),
            error: None,
            needs_permission: false,
            all: Vec::new(),
            settings: PickerSettings::default(),
            selected: 0,
            config: Config::default(),
            store,
            history,
            browsers,
            tab,
            settings_window: None,
            me: None,
            opened: None,
            clock,
            fixture: None,
        };
        picker.refresh();
        picker
    }

    /// The destinations the settings allow, favorites first.
    pub fn shown(&self) -> Vec<&Choice> {
        self.all.iter().filter(|c| self.settings.includes(&c.destination)).collect()
    }

    /// The favorite numbered `n` (1-based) among the shown destinations, for ⌘1–⌘9.
    pub fn favorite(&self, n: usize) -> Option<usize> {
        let shown = self.shown();
        shown.iter().enumerate().filter(|(_, c)| c.favorite).nth(n.checked_sub(1)?).map(|(i, _)| i)
    }

    /// Reads the saved config and lists the destinations again.
    pub fn refresh(&mut self) {
        if let Ok(snapshot) = self.store.load() {
            self.config = snapshot.config;
        }
        self.settings = self.config.picker.clone().unwrap_or_default();
        self.all = choices(&self.browsers.installed(), &self.settings);
        self.selected = self.selected.min(self.shown().len().saturating_sub(1));
    }

    /// The panel's height for what it shows now.
    pub fn height(&self) -> f32 {
        let shown = self.shown();
        let rows = shown.len().clamp(2, 6) as f32
            + shown.iter().take(6).filter(|c| c.error.is_some()).count() as f32 * 0.6;
        let error = if self.error.is_some() { 84.0 } else { 0.0 };
        150.0 + rows * ROW_H + error
    }

    /// The shortcut: remember the app in front, read its tab, and show the panel.
    pub fn summon(&mut self, tx: &mut Tx) {
        let front = self.tab.frontmost();
        self.link = TextEdit::new("");
        self.link.focused = true;
        self.error = None;
        self.needs_permission = false;
        self.opened = None;
        self.selected = 0;
        self.refresh();
        match (&front, &self.me) {
            (Some(app), Some(me)) => {
                let (tab, app, me) = (self.tab.clone(), app.clone(), me.clone());
                std::thread::spawn(move || {
                    let result = tab.read(&app);
                    me.update(move |p, _| p.tab_read(result));
                });
            }
            _ => self.tab_read(Err(TabError::UnsupportedBrowser)),
        }
        tx.resize_window_instant((WIDTH, self.height()));
        tx.settle();
        if let Some(me) = &self.me {
            me.place(
                rune::DisplayTarget::UnderPointer,
                rune::OverlayPlacement::Edge {
                    edge: rune::ScreenEdge::Top,
                    margin: 140.0,
                    align: rune::Align::Center,
                    inset: 0.0,
                },
            );
            me.show();
        }
    }

    /// What the tab reader found, from its worker.
    pub fn tab_read(&mut self, result: Result<String, TabError>) {
        match result {
            Ok(link) => {
                self.link = TextEdit::new(link);
                self.link.focused = true;
            }
            Err(e) => {
                self.error = Some(e.to_string());
                self.needs_permission = e == TabError::AutomationDenied;
            }
        }
    }

    /// Opens the link in the shown destination at `index`. The panel closes on success.
    pub fn open(&mut self, index: usize, tx: &mut Tx) {
        let Some(choice) = self.shown().get(index).map(|c| (*c).clone()) else { return };
        let link = self.link.text.trim().to_owned();
        if link.is_empty() && self.needs_permission {
            return;
        }
        if let Some(error) = &choice.error {
            self.error = Some(error.clone());
            return;
        }
        if !url::is_web(&link) {
            self.error = Some("Enter a complete HTTP or HTTPS link, such as https://example.com.".into());
            return;
        }
        if let Some(settings) = &self.settings_window {
            // Pending edits in Settings are saved; a manual pick ignores the rules either way.
            settings.update(|ui, _| {
                ui.editor.flush();
            });
        }
        let result =
            launch::launch(&link, &choice.destination, self.browsers.as_ref()).map_err(|e| e.to_string());
        let opened = Opened {
            url: &link,
            destination: &choice.destination,
            origin: Origin::Picker,
            config: &self.config,
            error: result.as_ref().err().cloned(),
            now: (self.clock)(),
        };
        history::record(&self.history, self.browsers.as_ref(), opened);
        match result {
            Ok(()) => {
                self.opened = Some((link, choice.destination.clone()));
                if let Some(browser) = self.browsers.at(&choice.destination.browser) {
                    self.tab.activate(&browser);
                }
                tx.close_window();
            }
            Err(e) => {
                self.error = Some(format!("{e} Refresh the destinations or open Settings to fix the issue."))
            }
        }
    }

    /// Stars or unstars a destination, saving through the settings window's editor so the two
    /// never write over each other.
    pub fn toggle_favorite(&mut self, index: usize) {
        let Some(choice) = self.shown().get(index).map(|c| (*c).clone()) else { return };
        let mut settings = self.settings.clone();
        if settings.favorites.iter().any(|f| f.destination() == choice.destination) {
            settings.favorites.retain(|f| f.destination() != choice.destination);
        } else if choice.error.is_none() {
            settings.favorites.push(Favorite {
                browser: choice.destination.browser.clone(),
                profile: choice.destination.profile.clone(),
                name: choice.profile_name.clone(),
            });
        }
        self.settings = settings.clone();
        self.all = choices(&self.browsers.installed(), &self.settings);
        match &self.settings_window {
            Some(window) => window.update(move |ui, _| {
                ui.editor.edit(|c| c.picker = Some(settings));
                ui.editor.flush();
            }),
            None => {
                // No settings window (tests and scenes): save directly, still compare-and-swap.
                if let Ok(snapshot) = self.store.load() {
                    let mut config = snapshot.config;
                    config.picker = Some(settings);
                    self.store.save(&config, Some(&snapshot.revision)).ok();
                }
            }
        }
    }

    pub fn open_settings(&mut self, tx: &mut Tx) {
        tx.close_window();
        if let Some(window) = &self.settings_window {
            window.update(|ui, tx| {
                ui.session.stay_resident();
                ui.go(crate::ui::Pane::QuickSwitch, tx);
            });
            window.open();
        }
    }

    /// Arrows move the selection, Return opens it, ⌘1–⌘9 open a favorite, Escape closes.
    pub fn on_key(&mut self, ev: &rune::KeyEvent, tx: &mut Tx) -> bool {
        use rune::Key;
        let count = self.shown().len();
        match &ev.key {
            Key::Escape => tx.close_window(),
            Key::Down if count > 0 => {
                tx.instant();
                self.selected = (self.selected + 1) % count;
            }
            Key::Up if count > 0 => {
                tx.instant();
                self.selected = (self.selected + count - 1) % count;
            }
            Key::Enter => self.open(self.selected, tx),
            Key::Command(c) => {
                let Some(n) = c.to_digit(10) else { return false };
                match self.favorite(n as usize) {
                    Some(i) => self.open(i, tx),
                    None => return false,
                }
            }
            _ => return false,
        }
        true
    }
}
