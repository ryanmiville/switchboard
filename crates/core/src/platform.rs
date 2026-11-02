//! What differs between macOS and Linux, as traits. `switchboard-macos` and `switchboard-linux`
//! implement them; the CLI and the app use only these traits. A trait here needs a real
//! implementation on each platform, never just a test double.

use std::path::PathBuf;

/// A supported Chromium browser on this machine.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BrowserInfo {
    /// What `config.json` stores for this browser: the `.app` path on macOS, the desktop entry's
    /// path on Linux.
    pub locator: String,
    /// The name people see, such as "Google Chrome".
    pub name: String,
    /// The bundle identifier on macOS, the desktop entry id on Linux.
    pub id: String,
    pub family: Family,
    /// Other names the browser goes by, such as "Chrome". Matched case-insensitively.
    pub aliases: Vec<String>,
    /// The program to run.
    pub executable: PathBuf,
    /// Arguments that go before Switchboard's, from a desktop entry's `Exec` line. Usually empty.
    pub args: Vec<String>,
    /// The browser's user-data folder, which holds `Local State` and the profiles.
    pub user_data: PathBuf,
}

impl BrowserInfo {
    /// Whether `query` names this browser: its name, an alias, or its family's short name (such
    /// as "Chrome"), ignoring case.
    pub fn answers_to(&self, query: &str) -> bool {
        std::iter::once(self.name.as_str())
            .chain(self.aliases.iter().map(String::as_str))
            .chain(self.family.short_name())
            .any(|n| n.eq_ignore_ascii_case(query))
    }
}

/// Finds supported Chromium browsers.
pub trait Browsers {
    /// Browsers installed in the usual places, sorted by name then locator.
    fn installed(&self) -> Vec<BrowserInfo>;

    /// The supported browser at `locator`, whether or not it is in the usual places. `None` when
    /// nothing is there or it isn't a supported Chromium browser.
    fn at(&self, locator: &str) -> Option<BrowserInfo>;

    /// `locator` in the form [`BrowserInfo::locator`] uses, so two spellings compare equal.
    fn standardize(&self, locator: &str) -> String {
        self.at(locator).map_or_else(|| locator.to_owned(), |b| b.locator)
    }

    /// The browser's name, or the locator's file name when it isn't available.
    fn display_name(&self, locator: &str) -> String {
        self.at(locator).map(|b| b.name).unwrap_or_else(|| file_stem(locator))
    }

    /// Installed browsers plus any supported browser at one of `extra` (such as those the config
    /// names), without duplicates, sorted by name then locator.
    fn known(&self, extra: &[String]) -> Vec<BrowserInfo> {
        let mut all = self.installed();
        for locator in extra {
            if let Some(info) = self.at(locator)
                && !all.iter().any(|b| b.locator == info.locator)
            {
                all.push(info);
            }
        }
        sort(&mut all);
        all
    }
}

/// Sorts browsers by name, ignoring case, then by locator.
pub fn sort(browsers: &mut [BrowserInfo]) {
    browsers
        .sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()).then(a.locator.cmp(&b.locator)));
}

/// The last path component without its extension (`/Applications/Helium.app` → `Helium`).
pub fn file_stem(locator: &str) -> String {
    std::path::Path::new(locator)
        .file_stem()
        .map_or_else(|| locator.to_owned(), |s| s.to_string_lossy().into_owned())
}

/// The Chromium browsers Switchboard supports, independent of platform. Each platform crate maps
/// a family to its bundle identifiers or desktop entries and its user-data folder, which are
/// browser-specific (not derived from the identifier).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Family {
    Chrome,
    ChromeBeta,
    ChromeDev,
    ChromeCanary,
    Chromium,
    Brave,
    Edge,
    EdgeBeta,
    EdgeDev,
    EdgeCanary,
    Opera,
    OperaBeta,
    OperaDeveloper,
    Vivaldi,
    Arc,
    Helium,
}

impl Family {
    /// A name people use for the browser that differs from its full name, if any.
    pub fn short_name(self) -> Option<&'static str> {
        match self {
            Family::Chrome => Some("Chrome"),
            Family::Edge => Some("Edge"),
            Family::Brave => Some("Brave"),
            _ => None,
        }
    }
}

/// Writes the program fixture browsers run in tests and scenes: it appends one line per launch to
/// `log`, with its arguments separated by tabs, and opens nothing.
pub fn write_recording_program(program: &std::path::Path, log: &std::path::Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    if let Some(dir) = program.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let script = format!(
        "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\t' \"$a\"; done >> '{}'\necho >> '{}'\n",
        log.display(),
        log.display()
    );
    std::fs::write(program, script)?;
    std::fs::set_permissions(program, std::fs::Permissions::from_mode(0o755))
}

/// The launches a recording program logged, oldest first, each as its argument list.
pub fn recorded_launches(log: &std::path::Path) -> Vec<Vec<String>> {
    std::fs::read_to_string(log)
        .unwrap_or_default()
        .lines()
        .map(|l| l.strip_suffix('\t').unwrap_or(l).split('\t').map(str::to_owned).collect())
        .collect()
}

/// Writes a `Local State` listing `profiles` as (directory, display name) pairs.
pub fn write_local_state(user_data: &std::path::Path, profiles: &[(&str, &str)]) -> std::io::Result<()> {
    std::fs::create_dir_all(user_data)?;
    let cache: serde_json::Map<String, serde_json::Value> =
        profiles.iter().map(|(dir, name)| ((*dir).to_owned(), serde_json::json!({ "name": name }))).collect();
    std::fs::write(
        user_data.join("Local State"),
        serde_json::json!({ "profile": { "info_cache": cache } }).to_string(),
    )
}
