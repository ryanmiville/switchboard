//! Browser icons stay decoded while the window shows them.

#[test]
fn an_icon_whose_handle_was_dropped_has_to_decode_again() {
    let ui = switchboard_app::fixture::ui();
    let cache = rune::ImageCache::new(std::sync::Arc::new(|| {}));
    let path = ui.editor.installed[0].locator.clone();
    cache.app_icon(&path, 16.0).wait().unwrap();
    // What the view did on every redraw: ask, draw, drop.
    let again = cache.app_icon(&path, 16.0);
    assert!(!again.is_ready(), "the cache keeps only icons someone holds");
}

#[test]
fn the_window_holds_each_icon_so_redraws_reuse_the_decoded_one() {
    let ui = switchboard_app::fixture::ui();
    let icons = switchboard_app::ui::icons::Icons::new(std::sync::Arc::new(|| {}));
    let path = ui.editor.installed[0].locator.clone();
    icons.get(&path, 16.0).wait().unwrap();
    assert!(icons.get(&path, 16.0).is_ready(), "a later redraw gets the decoded icon at once");
}
