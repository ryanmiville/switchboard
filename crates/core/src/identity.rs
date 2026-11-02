//! Names that change when the rewrite replaces the Swift app. Until then the Rust app uses its own
//! name, bundle identifier and folders, so the two can run side by side without the Swift app's
//! saves dropping fields it doesn't know.

/// The app's display name.
pub const APP_NAME: &str = "Switchboard RS";
/// The macOS bundle identifier.
pub const BUNDLE_ID: &str = "com.switchboard.rs";
/// The command-line tool's name.
pub const CLI_NAME: &str = "switchboard-rs";
/// The folder name under `~/.config` and `~/.local/state`.
pub const DIR_NAME: &str = "switchboard-rs";
/// The Swift app's config, relative to the home folder; the Rust app offers to import it.
pub const SWIFT_CONFIG: &str = ".config/switchboard/config.json";
