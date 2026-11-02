//! Switchboard's platform traits on macOS.
//!
//! Browser discovery only reads files (`Info.plist`, `Local State`), so it compiles and is tested
//! on every platform; the binaries use it on macOS only. AppKit glue (the status item, the login
//! item, reading the current tab) is compiled on macOS only.

pub mod browsers;
pub mod fixture;

pub use browsers::MacBrowsers;
use switchboard_core::{Env, Home};

/// Browsers in `/Applications` and `~/Applications`.
/// Or only the folders in `$SWITCHBOARD_RS_APPLICATIONS` when it is set.
pub fn browsers(home: &Home, env: &Env) -> MacBrowsers {
    let dirs =
        env.app_dirs.clone().unwrap_or_else(|| vec!["/Applications".into(), home.join("Applications")]);
    MacBrowsers::new(home.clone(), dirs)
}
