//! Everything Switchboard knows that isn't drawing or OS glue: the config file and its
//! compare-and-swap store, rule matching, rule edits, Chromium profiles, link history, launching,
//! and the traits each platform crate implements.
//!
//! Nothing here reads the environment, the clock or the real home folder on its own: callers pass
//! a [`Home`] and the current time, so tests run against temporary folders.

pub mod config;
pub mod error;
pub mod history;
pub mod home;
pub mod identity;
pub mod launch;
pub mod ops;
pub mod picker;
pub mod platform;
pub mod profiles;
pub mod router;
pub mod shadowing;
pub mod store;
pub mod time;
pub mod url;

pub use config::{Condition, Config, Destination, Rule};
pub use error::{Candidate, Code, OpError};
pub use home::{Env, Home};
pub use platform::{BrowserInfo, Browsers};
