//! End-to-end tests of the `switchboard-rs` binary. Each test gets a temporary home with fixture
//! browsers installed the way this platform installs them (app bundles on macOS, desktop entries on
//! Linux). Their programs record their arguments instead of opening anything, and
//! `$SWITCHBOARD_RS_APPLICATIONS` keeps the machine's real browsers out of view.

// Test helpers outside `#[test]` functions panic on purpose: a broken fixture is a failed test.
#![allow(clippy::unwrap_used, clippy::expect_used)]

mod cli {
    pub mod support;

    mod config_files;
    mod explain;
    mod history;
    mod launch;
    mod picker;
    mod route;
    mod rules;
    mod skill;
}
