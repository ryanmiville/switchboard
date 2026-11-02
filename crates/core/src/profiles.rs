//! Chromium profiles, read from a browser's `Local State`. Profiles are saved by directory
//! identifier (`Default`, `Profile 1`); display names are for people. Identical directory names in
//! two browsers can belong to different people, so a profile is always resolved within one browser.

use std::collections::BTreeMap;
use std::fs;
use std::io;

use serde::Deserialize;

use crate::config::Config;
use crate::platform::{BrowserInfo, Browsers};

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct Profile {
    /// The directory identifier, such as `Profile 1`.
    pub directory: String,
    /// The display name, such as `Work`.
    pub name: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ProfileError {
    /// No profile was chosen.
    SelectionRequired,
    /// The browser isn't installed, or isn't a supported Chromium browser.
    BrowserUnavailable(String),
    /// `Local State` exists but couldn't be read or parsed.
    Unreadable(String),
    Missing(String),
    Ambiguous(String),
}

impl std::fmt::Display for ProfileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ProfileError::SelectionRequired => {
                f.write_str("Choose a profile for every rule and for the default browser.")
            }
            ProfileError::BrowserUnavailable(locator) if locator.is_empty() => {
                f.write_str("No default browser is chosen. Choose one in Switchboard.")
            }
            ProfileError::BrowserUnavailable(locator) => {
                write!(f, "The browser at {locator} is unavailable. Choose an installed browser.")
            }
            ProfileError::Unreadable(why) => write!(f, "The browser's profiles couldn't be read. {why}"),
            ProfileError::Missing(name) => {
                write!(f, "The profile “{name}” is unavailable. Choose an existing profile.")
            }
            ProfileError::Ambiguous(name) => {
                write!(f, "Several profiles are named “{name}”. Choose the intended profile.")
            }
        }
    }
}

impl std::error::Error for ProfileError {}

/// The profiles in `browser`'s `Local State`, `Default` first, then by name. A browser that hasn't
/// written `Local State` yet has just `Default`.
pub fn read(browser: &BrowserInfo) -> Result<Vec<Profile>, ProfileError> {
    #[derive(Deserialize)]
    struct LocalState {
        profile: Option<Cache>,
    }
    #[derive(Deserialize)]
    struct Cache {
        info_cache: Option<BTreeMap<String, Info>>,
    }
    #[derive(Deserialize)]
    struct Info {
        name: Option<String>,
    }

    let path = browser.user_data.join("Local State");
    let default = || vec![Profile { directory: "Default".into(), name: "Default".into() }];
    let bytes = match fs::read(&path) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(default()),
        Err(e) => return Err(ProfileError::Unreadable(format!("{}: {e}.", path.display()))),
    };
    let state: LocalState = serde_json::from_slice(&bytes)
        .map_err(|e| ProfileError::Unreadable(format!("{}: {e}.", path.display())))?;
    let cache = state.profile.and_then(|p| p.info_cache).unwrap_or_default();
    let mut profiles: Vec<Profile> = cache
        .into_iter()
        .map(|(directory, info)| Profile { name: info.name.unwrap_or_else(|| directory.clone()), directory })
        .collect();
    if profiles.is_empty() {
        return Ok(default());
    }
    profiles.sort_by(|a, b| {
        (a.directory != "Default")
            .cmp(&(b.directory != "Default"))
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
            .then_with(|| a.directory.cmp(&b.directory))
    });
    Ok(profiles)
}

/// The profiles of the browser at `locator`.
pub fn of(browsers: &dyn Browsers, locator: &str) -> Result<Vec<Profile>, ProfileError> {
    let info = browsers.at(locator).ok_or_else(|| ProfileError::BrowserUnavailable(locator.to_owned()))?;
    read(&info)
}

/// The directory a saved profile names: a directory identifier first, then a display name that
/// only one profile has (older files saved display names).
pub fn directory(selection: &str, profiles: &[Profile]) -> Result<String, ProfileError> {
    if selection.is_empty() {
        return Err(ProfileError::SelectionRequired);
    }
    if profiles.iter().any(|p| p.directory == selection) {
        return Ok(selection.to_owned());
    }
    let named: Vec<_> = profiles.iter().filter(|p| p.name == selection).collect();
    match named.as_slice() {
        [one] => Ok(one.directory.clone()),
        [] => Err(ProfileError::Missing(selection.to_owned())),
        _ => Err(ProfileError::Ambiguous(selection.to_owned())),
    }
}

/// `config` with every profile saved as its directory identifier, each resolved in its own
/// destination's browser.
pub fn normalized(config: &Config, browsers: &dyn Browsers) -> Result<Config, ProfileError> {
    let mut cache: BTreeMap<String, Vec<Profile>> = BTreeMap::new();
    let mut resolve = |browser: &str, selection: &str| -> Result<String, ProfileError> {
        if !cache.contains_key(browser) {
            cache.insert(browser.to_owned(), of(browsers, browser)?);
        }
        directory(selection, &cache[browser])
    };
    let mut out = config.clone();
    out.default_profile = resolve(&config.browser, &config.default_profile)?;
    for (rule, original) in out.rules.iter_mut().zip(&config.rules) {
        rule.profile = resolve(config.browser_of(original), &original.profile)?;
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn profiles() -> Vec<Profile> {
        vec![
            Profile { directory: "Default".into(), name: "Ryan".into() },
            Profile { directory: "Profile 1".into(), name: "Profile 2".into() },
            Profile { directory: "Profile 2".into(), name: "Work".into() },
            Profile { directory: "Profile 3".into(), name: "Work".into() },
        ]
    }

    #[test]
    fn a_directory_identifier_wins_over_a_colliding_display_name() {
        assert_eq!(directory("Profile 2", &profiles()).unwrap(), "Profile 2");
    }

    #[test]
    fn a_unique_display_name_resolves_to_its_directory() {
        assert_eq!(directory("Ryan", &profiles()).unwrap(), "Default");
    }

    #[test]
    fn an_ambiguous_or_unknown_name_is_refused() {
        assert_eq!(directory("Work", &profiles()), Err(ProfileError::Ambiguous("Work".into())));
        assert_eq!(directory("Nobody", &profiles()), Err(ProfileError::Missing("Nobody".into())));
        assert_eq!(directory("", &profiles()), Err(ProfileError::SelectionRequired));
    }

    #[test]
    fn local_state_lists_default_first_then_by_name() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("Local State"),
            r#"{"profile":{"info_cache":{"Profile 2":{"name":"alpha"},"Default":{"name":"Zed"},"Profile 1":{}}}}"#,
        )
        .unwrap();
        let info = BrowserInfo {
            locator: "x".into(),
            name: "X".into(),
            id: "x".into(),
            family: crate::platform::Family::Chromium,
            aliases: vec![],
            executable: dir.path().join("x"),
            args: vec![],
            user_data: dir.path().to_owned(),
        };
        let names: Vec<_> = read(&info).unwrap().into_iter().map(|p| (p.directory, p.name)).collect();
        assert_eq!(
            names,
            [("Default", "Zed"), ("Profile 2", "alpha"), ("Profile 1", "Profile 1")]
                .map(|(d, n)| (d.to_owned(), n.to_owned()))
        );
        fs::remove_file(dir.path().join("Local State")).unwrap();
        assert_eq!(
            read(&info).unwrap(),
            vec![Profile { directory: "Default".into(), name: "Default".into() }]
        );
    }
}
