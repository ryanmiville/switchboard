use serde::Serialize;
use switchboard_core::OpError;
use switchboard_core::profiles;

use super::Output;
use crate::cli::Profiles;
use crate::format;
use crate::session::Session;

#[derive(Serialize)]
struct Report {
    browsers: Vec<BrowserReport>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct BrowserReport {
    name: String,
    /// What `--browser` and `config.json` take.
    path: String,
    /// The bundle identifier on macOS, the desktop entry id on Linux.
    id: String,
    is_default: bool,
    local_state: String,
    profiles: Vec<ProfileReport>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ProfileReport {
    profile: String,
    profile_name: String,
}

pub fn run(session: &Session<'_>, command: &Profiles) -> Result<Output, OpError> {
    let snapshot = session.load()?;
    let ops = session.ops(&snapshot);
    let browsers = match &command.browser {
        Some(query) => vec![ops.resolve_browser(query)?],
        None => ops.known_browsers(),
    };
    let default = session.context.browsers.standardize(&snapshot.config.browser);
    let reports: Vec<BrowserReport> = browsers
        .iter()
        .map(|info| {
            let (profiles, error) = match profiles::read(info) {
                Ok(list) => (
                    list.into_iter()
                        .map(|p| ProfileReport { profile: p.directory, profile_name: p.name })
                        .collect(),
                    None,
                ),
                Err(e) => (Vec::new(), Some(e.to_string())),
            };
            BrowserReport {
                name: info.name.clone(),
                path: info.locator.clone(),
                id: info.id.clone(),
                is_default: info.locator == default,
                local_state: info.user_data.join("Local State").to_string_lossy().into_owned(),
                profiles,
                error,
            }
        })
        .collect();
    let mut text =
        if reports.is_empty() { "No supported Chromium browsers found.\n".to_owned() } else { String::new() };
    for r in &reports {
        text += &format!(
            "{}{}  {}  ({})\n",
            r.name,
            if r.is_default { " (default browser)" } else { "" },
            r.path,
            r.id
        );
        if let Some(error) = &r.error {
            text += &format!("  ! {error}\n");
        }
        let width = r.profiles.iter().map(|p| p.profile.chars().count()).max().unwrap_or(0) + 2;
        for p in &r.profiles {
            text += &format!("  {}{}\n", format::padded(&p.profile, width), p.profile_name);
        }
    }
    Ok(Output::new(&Report { browsers: reports }, text))
}
