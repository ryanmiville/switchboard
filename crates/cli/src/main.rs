//! `switchboard-rs`: inspect and change how links are routed. Reads and writes the same files as
//! the app, with no daemon. Every command accepts `--json`. It never opens links.

mod cli;
mod commands;
mod format;
mod session;
mod skill;

use std::io::{IsTerminal, Write};
use std::process::ExitCode;

use switchboard_core::time::Timestamp;
use switchboard_core::{Env, OpError};

#[cfg(not(target_os = "macos"))]
use switchboard_linux as platform;
#[cfg(target_os = "macos")]
use switchboard_macos as platform;

fn main() -> ExitCode {
    let (home, env) = Env::from_process();
    let Some(home) = home else {
        eprintln!("error: $HOME isn't set.");
        return ExitCode::FAILURE;
    };
    #[expect(clippy::disallowed_methods, reason = "the binary reads the clock once and passes it in")]
    let now = Timestamp::from_system(std::time::SystemTime::now());
    let browsers = platform::browsers(&home, &env);
    let context =
        session::Context { home, env, now, browsers: &browsers, terminal: std::io::stdout().is_terminal() };
    let outcome = commands::run(std::env::args_os().collect(), &context);
    // A closed pipe (`| head`) is not an error worth reporting.
    std::io::stdout().write_all(outcome.stdout.as_bytes()).ok();
    std::io::stderr().write_all(outcome.stderr.as_bytes()).ok();
    ExitCode::from(outcome.status)
}

/// What a run prints and returns.
pub struct Outcome {
    pub status: u8,
    pub stdout: String,
    pub stderr: String,
}

impl Outcome {
    fn failure(error: &OpError, json: bool, terminal: bool) -> Outcome {
        if json {
            let body = serde_json::json!({ "error": error });
            return Outcome {
                status: error.code.exit_code(),
                stdout: format::json(&body, terminal),
                stderr: String::new(),
            };
        }
        let mut text = format!("error: {}\n", error.message);
        for candidate in &error.candidates {
            text += &format::candidate(candidate);
        }
        Outcome { status: error.code.exit_code(), stdout: String::new(), stderr: text }
    }
}
