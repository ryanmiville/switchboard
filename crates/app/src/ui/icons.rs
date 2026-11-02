//! Browser icons. Rune's `ImageCache` keeps an image only while a handle to it is alive, so the
//! window holds one handle per browser: asking the cache afresh on every view run would drop the
//! decoded icon between runs and decode it again, and a drag (a view run per frame) would make
//! the icons flicker.

use std::cell::RefCell;
use std::collections::HashMap;

/// Icon handles by browser locator, decoded off the main thread.
pub struct Icons {
    cache: rune::ImageCache,
    held: RefCell<HashMap<String, rune::Image>>,
}

impl Icons {
    pub fn new(wake: rune::Waker) -> Icons {
        Icons { cache: rune::ImageCache::new(wake), held: RefCell::default() }
    }

    /// The icon for the browser at `locator`, `size` points square. The same handle every time.
    pub fn get(&self, locator: &str, size: f32) -> rune::Image {
        self.held
            .borrow_mut()
            .entry(locator.to_owned())
            .or_insert_with(|| self.cache.app_icon(locator, size))
            .clone()
    }
}
