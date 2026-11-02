use std::path::PathBuf;
use std::process::Output;

use serde_json::Value;
use switchboard_core::Home;
use switchboard_core::platform::Family;

#[cfg(not(target_os = "macos"))]
pub use switchboard_linux as platform;
#[cfg(target_os = "macos")]
pub use switchboard_macos as platform;

const BIN: &str = env!("CARGO_BIN_EXE_switchboard-rs");

/// A temporary home with Helium (the default browser) and Google Chrome installed.
///
/// - Helium: `Default` "Ryan", `Profile 1` "Work".
/// - Chrome: `Default` "Chrome Ryan", `Profile 1` "Profile 2" (a display name colliding with a
///   directory), `Profile 2` "Work", `Profile 3` "Work" (an ambiguous name).
pub struct Fixture {
    _dir: tempfile::TempDir,
    pub home: Home,
    pub helium: String,
    pub chrome: String,
    pub launches: PathBuf,
}

pub struct Run {
    pub status: i32,
    pub stdout: String,
    pub stderr: String,
}

impl Run {
    pub fn json(&self) -> Value {
        serde_json::from_str(&self.stdout)
            .unwrap_or_else(|e| panic!("not JSON ({e}): {}\n{}", self.stdout, self.stderr))
    }

    #[track_caller]
    pub fn ok(self) -> Run {
        assert_eq!(self.status, 0, "stdout: {}\nstderr: {}", self.stdout, self.stderr);
        self
    }

    /// The JSON error code, for a run with `--json`.
    pub fn code(&self) -> String {
        self.json()["error"]["code"].as_str().unwrap_or_default().to_owned()
    }
}

impl Fixture {
    pub fn new() -> Fixture {
        let dir = tempfile::tempdir().unwrap();
        let home = Home::new(dir.path().canonicalize().unwrap());
        let launches = home.join("launches.log");
        let helium = platform::fixture::install_browser(
            &home,
            Family::Helium,
            "Helium",
            &[("Default", "Ryan"), ("Profile 1", "Work")],
            &launches,
        )
        .unwrap();
        let chrome = platform::fixture::install_browser(
            &home,
            Family::Chrome,
            "Google Chrome",
            &[
                ("Default", "Chrome Ryan"),
                ("Profile 1", "Profile 2"),
                ("Profile 2", "Work"),
                ("Profile 3", "Work"),
            ],
            &launches,
        )
        .unwrap();
        Fixture { _dir: dir, home, helium, chrome, launches }
    }

    pub fn config_path(&self) -> PathBuf {
        self.home.config_file()
    }

    /// Writes `config.json` with Helium · Default as the default and `rules` (JSON values).
    pub fn rules(&self, rules: Value) -> &Fixture {
        self.config(
            serde_json::json!({ "browser": self.helium, "defaultProfile": "Default", "rules": rules }),
        )
    }

    pub fn config(&self, config: Value) -> &Fixture {
        self.write_config(&serde_json::to_vec_pretty(&config).unwrap())
    }

    pub fn write_config(&self, bytes: &[u8]) -> &Fixture {
        std::fs::create_dir_all(self.config_path().parent().unwrap()).unwrap();
        std::fs::write(self.config_path(), bytes).unwrap();
        self
    }

    pub fn read_config(&self) -> Value {
        serde_json::from_slice(&std::fs::read(self.config_path()).unwrap()).unwrap()
    }

    pub fn config_bytes(&self) -> Vec<u8> {
        std::fs::read(self.config_path()).unwrap_or_default()
    }

    /// Appends history entries (JSON values), oldest first.
    pub fn history(&self, entries: &[Value]) -> &Fixture {
        let path = self.home.history_file();
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let text: String = entries.iter().map(|e| format!("{e}\n")).collect();
        std::fs::write(path, text).unwrap();
        self
    }

    pub fn apps(&self) -> PathBuf {
        platform::fixture::apps_dir(&self.home)
    }

    /// Runs the binary with only this fixture's home and browsers in view.
    pub fn run(&self, args: &[&str]) -> Run {
        #[expect(clippy::disallowed_methods, reason = "tests run the real binary")]
        let mut command = std::process::Command::new(BIN);
        command
            .args(args)
            .env_clear()
            .env("HOME", self.home.path())
            .env("PATH", "/usr/bin:/bin")
            .env("SWITCHBOARD_RS_APPLICATIONS", self.apps());
        let Output { status, stdout, stderr } = command.output().unwrap();
        Run {
            status: status.code().unwrap_or(-1),
            stdout: String::from_utf8(stdout).unwrap(),
            stderr: String::from_utf8(stderr).unwrap(),
        }
    }

    pub fn json(&self, args: &[&str]) -> Run {
        let mut all = args.to_vec();
        all.push("--json");
        self.run(&all)
    }
}

pub fn entry(id: &str, url: &str) -> Value {
    serde_json::json!({
        "id": id, "time": "2026-10-29T17:04:11Z", "url": url, "source": "default",
        "browser": "/nowhere/Helium.app", "profile": "Default", "result": "launched"
    })
}
