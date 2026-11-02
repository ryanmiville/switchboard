//! Opening a link that the system handed the app, and how long the app lives afterwards.

use switchboard_core::history::{self, HistoryStore, Opened, Origin};
use switchboard_core::time::Timestamp;
use switchboard_core::{Browsers, Config, launch, router};

/// Opens `link` where `config` routes it and records it in history. A history failure never
/// fails the link. Returns why the link couldn't be opened.
pub fn open(
    link: &str,
    config: &Config,
    browsers: &dyn Browsers,
    history: &HistoryStore,
    now: Timestamp,
) -> Result<(), String> {
    let decision = router::decide(config, link);
    let result = launch::launch(link, &decision.destination, browsers).map_err(|e| e.to_string());
    let origin = decision.rule.map_or(Origin::Default, Origin::Rule);
    let opened = Opened {
        url: link,
        destination: &decision.destination,
        origin,
        config,
        error: result.as_ref().err().cloned(),
        now,
    };
    // Best effort, and already kept for `doctor`.
    history::record(history, browsers, opened);
    result
}

/// When a link launch may quit. A launch that only delivers links exits shortly after the latest
/// one; opening the app any other way (at login, from the Dock or Finder, Settings) keeps it
/// running.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Session {
    received_link: bool,
    resident: bool,
    latest: u64,
}

/// Seconds a link-only launch waits after its latest link before quitting.
pub const IDLE_EXIT: f64 = 0.5;

impl Session {
    /// The app finished launching. Without a link it is a normal, resident launch.
    pub fn finish_launching(&mut self, at_login: bool) {
        if at_login || !self.received_link {
            self.resident = true;
        }
    }

    pub fn stay_resident(&mut self) {
        self.resident = true;
    }

    pub fn is_resident(&self) -> bool {
        self.resident
    }

    /// Returns a ticket for this link; only the latest ticket may quit the app.
    pub fn receive_link(&mut self) -> u64 {
        self.received_link = true;
        self.latest += 1;
        self.latest
    }

    pub fn should_quit_after(&self, ticket: u64) -> bool {
        self.received_link && !self.resident && ticket == self.latest
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_link_only_launch_quits_after_its_latest_link() {
        let mut s = Session::default();
        let first = s.receive_link();
        s.finish_launching(false);
        let second = s.receive_link();
        assert!(!s.should_quit_after(first));
        assert!(s.should_quit_after(second));
    }

    #[test]
    fn opening_settings_or_launching_at_login_keeps_the_app_running() {
        let mut s = Session::default();
        let t = s.receive_link();
        s.finish_launching(true);
        assert!(!s.should_quit_after(t));

        let mut s = Session::default();
        let t = s.receive_link();
        s.finish_launching(false);
        s.stay_resident();
        assert!(!s.should_quit_after(t));
    }

    #[test]
    fn a_normal_launch_is_resident() {
        let mut s = Session::default();
        s.finish_launching(false);
        let t = s.receive_link();
        assert!(!s.should_quit_after(t));
    }
}
