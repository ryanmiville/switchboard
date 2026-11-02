//! Fixture browsers for tests and scenes: real desktop entries in a temporary folder whose program
//! records its arguments instead of opening anything.

use std::path::Path;

use switchboard_core::Home;
use switchboard_core::platform::{Family, write_local_state, write_recording_program};

use crate::browsers::ENTRIES;

/// The folder fixture browsers go in; point `$SWITCHBOARD_RS_APPLICATIONS` at it.
pub fn apps_dir(home: &Home) -> std::path::PathBuf {
    home.join(".local/share/applications")
}

/// Installs `<apps>/<id>` as a browser of `family` named `name`, gives it `profiles` (directory,
/// name), and returns its locator. Its program appends each launch to `log`.
pub fn install_browser(
    home: &Home,
    family: Family,
    name: &str,
    profiles: &[(&str, &str)],
    log: &Path,
) -> std::io::Result<String> {
    let apps = &apps_dir(home);
    let (id, _, data) = ENTRIES
        .iter()
        .find(|(_, f, _)| *f == family)
        .ok_or_else(|| std::io::Error::other("unsupported family"))?;
    let program = home.join("fixture-bin").join(id.trim_end_matches(".desktop"));
    write_recording_program(&program, log)?;
    std::fs::create_dir_all(apps)?;
    let entry = apps.join(id);
    std::fs::write(
        &entry,
        format!("[Desktop Entry]\nType=Application\nName={name}\nExec=\"{}\" %U\n", program.display()),
    )?;
    write_local_state(&home.join(".config").join(data), profiles)?;
    Ok(entry.to_string_lossy().into_owned())
}
