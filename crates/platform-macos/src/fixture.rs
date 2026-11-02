//! Fixture browsers for tests and scenes: real app bundles in a temporary folder whose program
//! records its arguments instead of opening anything.

use std::path::Path;

use switchboard_core::Home;
use switchboard_core::platform::{Family, write_local_state, write_recording_program};

use crate::browsers::BUNDLES;

/// The folder fixture browsers go in; point `$SWITCHBOARD_RS_APPLICATIONS` at it.
pub fn apps_dir(home: &Home) -> std::path::PathBuf {
    home.join("Applications")
}

/// Installs `<apps>/<name>.app` as a browser of `family`, gives it `profiles` (directory, name),
/// and returns its locator. Its program appends each launch to `log`.
pub fn install_browser(
    home: &Home,
    family: Family,
    name: &str,
    profiles: &[(&str, &str)],
    log: &Path,
) -> std::io::Result<String> {
    let apps = &apps_dir(home);
    let (id, _, data) = BUNDLES
        .iter()
        .find(|(_, f, _)| *f == family)
        .ok_or_else(|| std::io::Error::other("unsupported family"))?;
    let app = apps.join(format!("{name}.app"));
    let exe = name.replace(' ', "");
    std::fs::create_dir_all(app.join("Contents/MacOS"))?;
    std::fs::write(
        app.join("Contents/Info.plist"),
        format!(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>{id}</string>
  <key>CFBundleExecutable</key><string>{exe}</string>
  <key>CFBundleName</key><string>{name}</string>
</dict></plist>
"#
        ),
    )?;
    write_recording_program(&app.join("Contents/MacOS").join(&exe), log)?;
    write_local_state(&home.join("Library/Application Support").join(data), profiles)?;
    Ok(app.to_string_lossy().into_owned())
}
