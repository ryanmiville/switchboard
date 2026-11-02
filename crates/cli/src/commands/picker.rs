use switchboard_core::OpError;
use switchboard_core::config::{Config, Destination};
use switchboard_core::ops::Ops;
use switchboard_core::picker::{Favorite, PickerSettings, Shortcut};

use super::{Output, change_setting};
use crate::cli::Picker;
use crate::session::Session;

fn settings(config: &Config) -> PickerSettings {
    config.picker.clone().unwrap_or_default()
}

fn describe(config: &Config) -> String {
    let s = settings(config);
    let shown = match &s.destinations {
        None => "every destination".to_owned(),
        Some(d) => format!("{} destination{}", d.len(), if d.len() == 1 { "" } else { "s" }),
    };
    format!("the picker: shortcut {}, {} favorites, showing {shown}.", s.shortcut.as_str(), s.favorites.len())
}

/// Resolves a browser and profile the way `route` does, into what the config saves.
fn destination(ops: &Ops<'_>, browser: &str, profile: &str) -> Result<(Destination, String), OpError> {
    let info = ops.resolve_browser(browser)?;
    let profile = ops.resolve_profile(profile, &info.locator)?;
    Ok((Destination { browser: info.locator, profile: profile.directory }, profile.name))
}

pub fn run(session: &Session<'_>, command: &Picker) -> Result<Output, OpError> {
    let value = |config: &Config| settings(config);
    match command {
        Picker::Show => {
            let snapshot = session.load()?;
            let s = settings(&snapshot.config);
            let mut text = format!("Shortcut: {}\n", s.shortcut.as_str());
            text += if s.favorites.is_empty() { "No favorites.\n" } else { "Favorites:\n" };
            for f in &s.favorites {
                text += &format!(
                    "  {}  {} · {}\n",
                    f.name,
                    session.context.browsers.display_name(&f.browser),
                    f.profile
                );
            }
            match &s.destinations {
                None => text += "Shows every installed destination.\n",
                Some(list) => {
                    text += &format!("Shows {} destinations:\n", list.len());
                    for d in list {
                        text += &format!(
                            "  {} · {}\n",
                            session.context.browsers.display_name(&d.browser),
                            d.profile
                        );
                    }
                }
            }
            let report = serde_json::json!({ "picker": s, "revision": snapshot.revision });
            Ok(Output::new(&report, text))
        }
        Picker::Shortcut { shortcut, change } => change_setting(
            session,
            change,
            |_, config| {
                let shortcut = shortcut.trim().to_lowercase();
                if !shortcut.contains('+') || shortcut.ends_with('+') {
                    return Err(OpError::invalid(
                        "Write a shortcut as modifiers and a key, such as ctrl+alt+space.",
                    ));
                }
                let mut s = settings(config);
                s.shortcut = Shortcut::new(shortcut);
                config.picker = Some(s);
                Ok(())
            },
            value,
            describe,
        ),
        Picker::Favorite { browser, profile, name, change } => change_setting(
            session,
            change,
            |ops, config| {
                let (d, profile_name) = destination(ops, browser, profile)?;
                let mut s = settings(config);
                let label = name.clone().unwrap_or(profile_name);
                match s.favorites.iter_mut().find(|f| f.destination() == d) {
                    Some(existing) => existing.name = label,
                    None => {
                        s.favorites.push(Favorite { browser: d.browser, profile: d.profile, name: label })
                    }
                }
                config.picker = Some(s);
                Ok(())
            },
            value,
            describe,
        ),
        Picker::Unfavorite { browser, profile, change } => change_setting(
            session,
            change,
            |ops, config| {
                let (d, _) = destination(ops, browser, profile)?;
                let mut s = settings(config);
                s.favorites.retain(|f| f.destination() != d);
                config.picker = Some(s);
                Ok(())
            },
            value,
            describe,
        ),
        Picker::Destination { browser, profile, hide, only, change } => change_setting(
            session,
            change,
            |ops, config| {
                let (d, _) = destination(ops, browser, profile)?;
                let mut s = settings(config);
                // Hiding one destination from "show everything" starts an explicit list of the rest.
                if *only {
                    s.destinations = Some(vec![d]);
                    config.picker = Some(s);
                    return Ok(());
                }
                let mut shown = s.destinations.clone().unwrap_or_else(|| {
                    let mut all = Vec::new();
                    for info in ops.known_browsers() {
                        if let Ok(list) = ops.profiles(&info.locator) {
                            all.extend(list.into_iter().map(|p| Destination {
                                browser: info.locator.clone(),
                                profile: p.directory,
                            }));
                        }
                    }
                    all
                });
                shown.retain(|x| *x != d);
                if !hide {
                    shown.push(d);
                }
                s.destinations = Some(shown);
                config.picker = Some(s);
                Ok(())
            },
            value,
            describe,
        ),
        Picker::ShowAll(change) => change_setting(
            session,
            change,
            |_, config| {
                let mut s = settings(config);
                s.destinations = None;
                config.picker = Some(s);
                Ok(())
            },
            value,
            describe,
        ),
    }
}
