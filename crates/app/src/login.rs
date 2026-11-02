//! Launch at login, as the settings window shows it. The platform's calls can block (macOS asks
//! a system service), so they run on a worker thread; results come back through `poll`.
//!
//! Headless runs and tests have no worker: they never touch the real login items, and a toggle
//! there only changes what the window shows.

use std::sync::mpsc::{Receiver, Sender, channel};

use switchboard_core::platform::{LoginItem, LoginStatus};

enum Request {
    Status,
    Set(bool),
    OpenSettings,
}

struct Worker {
    requests: Sender<Request>,
    results: Receiver<Result<LoginStatus, String>>,
}

pub struct Login {
    /// `None` until the first answer arrives.
    pub status: Option<LoginStatus>,
    pub error: Option<String>,
    worker: Option<Worker>,
}

impl Login {
    /// No worker: what headless runs and tests use.
    pub fn shown(status: LoginStatus) -> Login {
        Login { status: Some(status), error: None, worker: None }
    }

    /// Starts the worker over the real login item and asks for its status. `wake` wakes the
    /// app's poll when an answer arrives.
    pub fn start(item: Box<dyn LoginItem>, wake: rune::Waker) -> Login {
        let (requests, inbox) = channel::<Request>();
        let (outbox, results) = channel();
        std::thread::Builder::new()
            .name("login-item".into())
            .spawn(move || {
                for request in inbox {
                    let result = match request {
                        Request::Status => item.status(),
                        Request::Set(enabled) => item.set_enabled(enabled),
                        Request::OpenSettings => {
                            item.open_settings();
                            item.status()
                        }
                    };
                    if outbox.send(result).is_err() {
                        break;
                    }
                    wake();
                }
            })
            .ok();
        // The worker is gone only if the thread couldn't start; the row then says so.
        let worker = Worker { requests, results };
        worker.requests.send(Request::Status).ok();
        Login { status: None, error: None, worker: Some(worker) }
    }

    pub fn set_enabled(&mut self, enabled: bool) {
        self.error = None;
        match &self.worker {
            Some(w) => {
                w.requests.send(Request::Set(enabled)).ok();
            }
            None => self.status = Some(if enabled { LoginStatus::Enabled } else { LoginStatus::Disabled }),
        }
    }

    pub fn open_settings(&mut self) {
        if let Some(w) = &self.worker {
            w.requests.send(Request::OpenSettings).ok();
        }
    }

    /// Re-reads the status, for when the window comes forward (the person may have changed it in
    /// System Settings).
    pub fn refresh(&mut self) {
        if let Some(w) = &self.worker {
            w.requests.send(Request::Status).ok();
        }
    }

    /// Takes the worker's answers. Returns true when what the window shows changed.
    pub fn drain(&mut self) -> bool {
        let Some(w) = &self.worker else { return false };
        let mut changed = false;
        while let Ok(result) = w.results.try_recv() {
            let before = (self.status, self.error.clone());
            match result {
                Ok(status) => {
                    self.status = Some(status);
                    self.error = None;
                }
                Err(e) => self.error = Some(format!("Open at login couldn't be changed. {e}")),
            }
            changed |= before != (self.status, self.error.clone());
        }
        changed
    }
}
