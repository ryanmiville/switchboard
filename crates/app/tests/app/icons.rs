//! Browser icons stay decoded while the window shows them.
//!
//! Rune's `ImageCache` keeps an image only while a handle is alive; a view that asked for each
//! icon afresh and dropped it decoded it again on every redraw, so icons flickered during a drag.
//! (A test of that cause raced the cache's worker, which can finish the second decode before
//! anything checks, so only the fix is tested.)

#[test]
fn the_window_holds_each_icon_so_redraws_reuse_the_decoded_one() {
    let ui = switchboard_app::fixture::ui();
    let icons = switchboard_app::ui::icons::Icons::new(std::sync::Arc::new(|| {}));
    let path = ui.editor.installed[0].locator.clone();
    let first = icons.get(&path, 16.0);
    first.wait().unwrap();
    drop(first);
    assert!(icons.get(&path, 16.0).is_ready(), "a later redraw gets the decoded icon at once");
}
