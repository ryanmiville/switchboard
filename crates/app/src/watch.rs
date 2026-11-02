//! Follows `config.json` while the app runs, so changes made through `switchboard-rs` show up in
//! an open Settings window and reach the picker. A small thread compares the file's size and
//! modification time twice a second: cheap, portable, and it survives the atomic rename every
//! save does (a watch on the file itself would follow the replaced inode).

use std::path::PathBuf;
use std::time::Duration;

const INTERVAL: Duration = Duration::from_millis(500);

/// Calls `on_change` whenever the file at `path` appears, disappears, or changes.
pub fn watch(path: PathBuf, on_change: impl Fn() + Send + 'static) {
    let stamp = move || std::fs::metadata(&path).ok().map(|m| (m.modified().ok(), m.len()));
    let mut last = stamp();
    std::thread::Builder::new()
        .name("config-watch".into())
        .spawn(move || {
            loop {
                std::thread::sleep(INTERVAL);
                let now = stamp();
                if now != last {
                    last = now;
                    on_change();
                }
            }
        })
        .ok();
}
