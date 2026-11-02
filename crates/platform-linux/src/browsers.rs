//! Chromium browsers as XDG desktop entries. A browser is identified by its desktop entry id
//! (`google-chrome.desktop`); its profiles live in a folder under `~/.config` that each browser
//! names its own way.
//!
//! Gap: Flatpak and Snap browsers keep their profiles in sandbox folders and aren't supported yet.

use std::path::{Path, PathBuf};

use switchboard_core::Home;
use switchboard_core::platform::{self, BrowserInfo, Browsers, Family};

/// Desktop entry ids, the family each belongs to, and its user-data folder under `~/.config`.
pub const ENTRIES: &[(&str, Family, &str)] = &[
    ("google-chrome.desktop", Family::Chrome, "google-chrome"),
    ("google-chrome-beta.desktop", Family::ChromeBeta, "google-chrome-beta"),
    ("google-chrome-unstable.desktop", Family::ChromeDev, "google-chrome-unstable"),
    ("chromium.desktop", Family::Chromium, "chromium"),
    ("chromium-browser.desktop", Family::Chromium, "chromium"),
    ("brave-browser.desktop", Family::Brave, "BraveSoftware/Brave-Browser"),
    ("microsoft-edge.desktop", Family::Edge, "microsoft-edge"),
    ("microsoft-edge-beta.desktop", Family::EdgeBeta, "microsoft-edge-beta"),
    ("microsoft-edge-dev.desktop", Family::EdgeDev, "microsoft-edge-dev"),
    ("opera.desktop", Family::Opera, "opera"),
    ("vivaldi-stable.desktop", Family::Vivaldi, "vivaldi"),
    ("helium.desktop", Family::Helium, "net.imput.helium"),
];

#[derive(Clone, Debug)]
pub struct LinuxBrowsers {
    home: Home,
    app_dirs: Vec<PathBuf>,
    path: Vec<PathBuf>,
}

impl LinuxBrowsers {
    /// Browsers whose desktop entries are in `app_dirs`; programs named without a path are looked
    /// up in `path`.
    pub fn new(home: Home, app_dirs: Vec<PathBuf>, path: Vec<PathBuf>) -> Self {
        LinuxBrowsers { home, app_dirs, path }
    }

    fn find_program(&self, name: &str) -> PathBuf {
        if name.contains('/') {
            return PathBuf::from(name);
        }
        self.path.iter().map(|d| d.join(name)).find(|p| p.is_file()).unwrap_or_else(|| PathBuf::from(name))
    }
}

impl Browsers for LinuxBrowsers {
    fn installed(&self) -> Vec<BrowserInfo> {
        let mut found: Vec<BrowserInfo> = Vec::new();
        for dir in &self.app_dirs {
            for (id, _, _) in ENTRIES {
                let path = dir.join(id);
                if found.iter().any(|b| b.id == *id) || !path.is_file() {
                    continue;
                }
                if let Some(info) = self.at(&path.to_string_lossy()) {
                    found.push(info);
                }
            }
        }
        platform::sort(&mut found);
        found
    }

    fn at(&self, locator: &str) -> Option<BrowserInfo> {
        let path = Path::new(locator);
        let id = path.file_name()?.to_str()?.to_owned();
        let (_, family, data) = ENTRIES.iter().find(|(e, _, _)| *e == id)?;
        let entry = std::fs::read_to_string(path).ok()?;
        let fields = desktop_entry(&entry);
        let field = |key: &str| fields.iter().find(|(k, _)| *k == key).map(|(_, v)| *v);
        let name = field("Name")?.to_owned();
        let mut exec = split_exec(field("Exec")?).into_iter();
        let program = self.find_program(&exec.next()?);
        Some(BrowserInfo {
            locator: locator.to_owned(),
            aliases: field("GenericName")
                .filter(|g| !g.contains(' '))
                .map(str::to_owned)
                .into_iter()
                .collect(),
            name,
            id: id.clone(),
            family: *family,
            executable: program,
            args: exec.collect(),
            user_data: self.home.join(".config").join(data),
        })
    }
}

/// The `key=value` pairs of the `[Desktop Entry]` group, skipping localized keys.
fn desktop_entry(text: &str) -> Vec<(&str, &str)> {
    let mut in_group = false;
    let mut out = Vec::new();
    for line in text.lines().map(str::trim) {
        if line.starts_with('[') {
            in_group = line == "[Desktop Entry]";
        } else if in_group
            && let Some((key, value)) = line.split_once('=')
            && !key.contains('[')
        {
            out.push((key.trim(), value.trim()));
        }
    }
    out
}

/// Splits an `Exec` value into arguments, honouring double quotes and dropping field codes such as
/// `%U`.
fn split_exec(exec: &str) -> Vec<String> {
    let mut args = Vec::new();
    let mut current = String::new();
    let (mut quoted, mut escaped, mut started) = (false, false, false);
    for c in exec.chars() {
        match c {
            _ if escaped => {
                current.push(c);
                escaped = false;
            }
            '\\' if quoted => escaped = true,
            '"' => {
                quoted = !quoted;
                started = true;
            }
            ' ' | '\t' if !quoted => {
                if started {
                    args.push(std::mem::take(&mut current));
                    started = false;
                }
            }
            _ => {
                current.push(c);
                started = true;
            }
        }
    }
    if started {
        args.push(current);
    }
    args.retain(|a| !(a.len() == 2 && a.starts_with('%')));
    args.iter().map(|a| a.replace("%%", "%")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exec_lines_split_on_spaces_outside_quotes_and_drop_field_codes() {
        assert_eq!(split_exec(r#"/usr/bin/google-chrome-stable %U"#), ["/usr/bin/google-chrome-stable"]);
        assert_eq!(split_exec(r#""/opt/My Browser/run" --flag %u"#), ["/opt/My Browser/run", "--flag"]);
    }

    #[test]
    fn only_the_desktop_entry_group_is_read() {
        let text = "[Desktop Entry]\nName=Google Chrome\nName[de]=X\nExec=a\n[Desktop Action new]\nName=New Window\n";
        assert_eq!(desktop_entry(text), [("Name", "Google Chrome"), ("Exec", "a")]);
    }
}
