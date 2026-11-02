//! The state scenes and tests start from: a temporary home with fixture Helium and Chrome
//! installs (real bundles or desktop entries whose programs only record their arguments), a
//! config, and some history. Never the real home.

// A fixture that can't be built is a broken test setup; failing loudly is the point.
#![expect(clippy::expect_used, reason = "fixture setup failures should stop the run")]

use serde_json::json;
use switchboard_core::history::HistoryStore;
use switchboard_core::platform::Family;
use switchboard_core::store::ConfigStore;
use switchboard_core::{Env, Home};

use std::sync::Arc;

use switchboard_core::time::Timestamp;

use crate::editor::Editor;
use crate::picker::Picker;
use crate::platform;
use crate::ui::Ui;

/// Browsers and the locators the fixture installed.
pub struct Installed {
    pub helium: String,
    pub chrome: String,
}

/// Installs the fixture browsers into `home`.
pub fn install(home: &Home) -> Installed {
    let log = home.join("launches.log");
    let helium = platform::fixture::install_browser(
        home,
        Family::Helium,
        "Helium",
        &[("Default", "Ryan"), ("Profile 1", "Work")],
        &log,
    )
    .expect("fixture Helium installs");
    let chrome = platform::fixture::install_browser(
        home,
        Family::Chrome,
        "Google Chrome",
        &[("Default", "Chrome Ryan"), ("Profile 2", "Work"), ("Profile 3", "Side project")],
        &log,
    )
    .expect("fixture Chrome installs");
    Installed { helium, chrome }
}

/// An editor over `home`, seeing only the fixture browsers.
pub fn editor(home: &Home) -> Editor {
    let env = Env { app_dirs: Some(vec![platform::fixture::apps_dir(home)]), ..Env::default() };
    Editor::open(
        home.clone(),
        ConfigStore::new(home.config_file()),
        HistoryStore::new(home.history_file()),
        Box::new(platform::browsers(home, &env)),
    )
}

/// A temporary home with the fixture browsers and config.
fn home() -> (tempfile::TempDir, Home) {
    let dir =
        tempfile::Builder::new().prefix("switchboard-rs-fixture").tempdir().expect("a temporary folder");
    let home = Home::new(dir.path());
    let b = install(&home);
    let config = json!({
        "browser": b.helium,
        "defaultProfile": "Default",
        "rules": [
            { "condition": "domain", "value": "github.com", "profile": "Profile 1" },
            { "condition": "contains", "value": "acme", "profile": "Profile 2", "browser": b.chrome },
            { "condition": "domain", "value": "docs.github.com", "profile": "Default" },
            { "condition": "exact", "value": "https://example.com/login", "profile": "Profile 3", "browser": b.chrome },
        ],
        "picker": {
            "shortcut": "ctrl+alt+space",
            "favorites": [ { "browser": b.helium, "profile": "Default", "name": "Ryan" } ],
        },
    });
    let path = home.config_file();
    std::fs::create_dir_all(path.parent().expect("a folder")).expect("the config folder");
    std::fs::write(&path, serde_json::to_vec_pretty(&config).expect("JSON")).expect("the config");
    (dir, home)
}

/// The fixture state: Helium is the default; four rules, one of them hidden by another.
pub fn ui() -> Ui {
    let (dir, home) = home();
    let mut ui = Ui::new(editor(&home));
    ui.fixture = Some(dir);
    ui
}

/// The fixture picker over the same home. Tests and scenes never summon it, so it never reads a
/// real browser's tab: its link is set directly.
pub fn picker() -> Picker {
    let (dir, home) = home();
    let env = Env { app_dirs: Some(vec![platform::fixture::apps_dir(&home)]), ..Env::default() };
    let mut picker = Picker::new(
        ConfigStore::new(home.config_file()),
        HistoryStore::new(home.history_file()),
        Box::new(platform::browsers(&home, &env)),
        Arc::new(platform::PlatformCurrentTab),
        || Timestamp(1_761_757_451),
    );
    picker.link = rune::TextEdit::new("https://github.com/acme/api/pull/12");
    picker.fixture = Some(dir);
    picker
}
