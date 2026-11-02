//! Reading the current tab isn't possible on Linux: browsers expose no common automation
//! interface there. Quick Switch shows its paste field instead.

use switchboard_core::platform::{BrowserInfo, CurrentTab, Frontmost, TabError};

pub struct NoCurrentTab;

impl CurrentTab for NoCurrentTab {
    fn frontmost(&self) -> Option<Frontmost> {
        None
    }

    fn read(&self, _app: &Frontmost) -> Result<String, TabError> {
        Err(TabError::UnsupportedBrowser)
    }

    fn activate(&self, _browser: &BrowserInfo) {}
}
