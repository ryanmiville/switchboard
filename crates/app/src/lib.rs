//! The Switchboard app: the settings window, link routing for the app's lifetime, and the named
//! scenes every headless render and test starts from.

pub mod editor;
pub mod fixture;
pub mod login;
pub mod routing;
pub mod scenes;
pub mod ui;

#[cfg(not(target_os = "macos"))]
pub use switchboard_linux as platform;
#[cfg(target_os = "macos")]
pub use switchboard_macos as platform;

use rune::AppSpec;
use switchboard_core::identity;
use ui::Ui;

/// The window's one fixed size: tiling window managers float it instead of stretching it.
pub const SIZE: (f32, f32) = (860.0, 620.0);

/// The app's spec. Its `init` builds the fixture state, so headless renders and tests never read
/// the real home; the binary replaces it for a real run.
pub fn spec() -> AppSpec<Ui> {
    AppSpec {
        min_size: Some(SIZE),
        scenes: scenes::SCENES,
        poll: Some(|ui, now, tx| ui.poll(now, tx)),
        setup: Some(|ui, wake| {
            if let Some(item) = ui.login_item.take() {
                ui.login = login::Login::start(item, wake);
            }
        }),
        on_key: Some(|ui, ev, tx| ui.on_key(ev, tx)),
        ..AppSpec::new(identity::APP_NAME, SIZE, fixture::ui, ui::view)
    }
}
