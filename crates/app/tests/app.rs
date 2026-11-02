//! The app driven headless: Rune's runtime with no window or GPU, over the real editor and store
//! in a temporary home with fixture browsers. Goldens render through the app binary's `--snap`.

// Test helpers outside `#[test]` functions panic on purpose: a broken fixture is a failed test.
#![allow(clippy::unwrap_used, clippy::expect_used)]

mod app {
    pub mod support;

    mod editor;
    mod goldens;
    mod links;
    mod scenes;
    mod settings;
}
