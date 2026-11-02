//! Switchboard's platform traits on macOS.
//!
//! Browser discovery only reads files (`Info.plist`, `Local State`), so it compiles and is tested
//! on every platform; the binaries use it on macOS only. AppKit glue (the status item, the login
//! item, reading the current tab) is compiled on macOS only.

pub mod browsers;
#[cfg(target_os = "macos")]
pub mod current_tab;
pub mod fixture;
#[cfg(target_os = "macos")]
pub mod login_item;
#[cfg(target_os = "macos")]
pub mod menu_bar;

pub use browsers::MacBrowsers;
#[cfg(target_os = "macos")]
pub use current_tab::MacCurrentTab as PlatformCurrentTab;
#[cfg(target_os = "macos")]
pub use login_item::MacLoginItem;
#[cfg(target_os = "macos")]
pub use menu_bar::{MacMenuBar as PlatformMenuBar, bring_to_front};

/// Not a menu-bar app off macOS: kept so the crate builds everywhere.
#[cfg(not(target_os = "macos"))]
pub fn bring_to_front() {}
use switchboard_core::{Env, Home};

/// Browsers in `/Applications` and `~/Applications`.
/// Or only the folders in `$SWITCHBOARD_RS_APPLICATIONS` when it is set.
pub fn browsers(home: &Home, env: &Env) -> MacBrowsers {
    let dirs =
        env.app_dirs.clone().unwrap_or_else(|| vec!["/Applications".into(), home.join("Applications")]);
    MacBrowsers::new(home.clone(), dirs)
}

/// Launch at login for the app bundle this process runs from. `program` is unused on macOS.
#[cfg(target_os = "macos")]
pub fn login_item(_home: &Home, _program: std::path::PathBuf) -> MacLoginItem {
    MacLoginItem
}
