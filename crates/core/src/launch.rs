//! Opening a link in a browser profile. The browser's executable is run directly with an argument
//! array (`--profile-directory=<dir> <link>`), never through `open -a`, so the profile is honoured
//! when the browser is already running. The link is passed exactly as it arrived.

use std::path::PathBuf;
use std::process::Stdio;

use crate::config::Destination;
use crate::platform::Browsers;
use crate::profiles::{self, ProfileError};
use crate::url;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LaunchError {
    InvalidUrl,
    Profile(ProfileError),
    NotExecutable(PathBuf),
    Spawn(String),
}

impl std::fmt::Display for LaunchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LaunchError::InvalidUrl => {
                f.write_str("Switchboard can only open complete HTTP or HTTPS links and local files.")
            }
            LaunchError::Profile(error) => error.fmt(f),
            LaunchError::NotExecutable(path) => {
                write!(
                    f,
                    "The browser's program at {} can't be run. Reinstall the browser or choose another.",
                    path.display()
                )
            }
            LaunchError::Spawn(why) => write!(f, "The browser couldn't be started. {why}"),
        }
    }
}

impl std::error::Error for LaunchError {}

/// The program and arguments that open `link` at `destination`, after checking both.
pub fn command(
    link: &str,
    destination: &Destination,
    browsers: &dyn Browsers,
) -> Result<(PathBuf, Vec<String>), LaunchError> {
    if !(url::is_web(link) || url::is_local_file(link)) {
        return Err(LaunchError::InvalidUrl);
    }
    let browser = browsers
        .at(&destination.browser)
        .ok_or_else(|| LaunchError::Profile(ProfileError::BrowserUnavailable(destination.browser.clone())))?;
    if !is_executable(&browser.executable) {
        return Err(LaunchError::NotExecutable(browser.executable));
    }
    let available = profiles::read(&browser).map_err(LaunchError::Profile)?;
    let directory = profiles::directory(&destination.profile, &available).map_err(LaunchError::Profile)?;
    let mut args = browser.args;
    args.push(format!("--profile-directory={directory}"));
    args.push(link.to_owned());
    Ok((browser.executable, args))
}

/// Starts the browser and returns once it has started. The child is reaped on a background
/// thread, so a resident app collects no zombies.
pub fn launch(link: &str, destination: &Destination, browsers: &dyn Browsers) -> Result<(), LaunchError> {
    let (program, args) = command(link, destination, browsers)?;
    #[expect(clippy::disallowed_methods, reason = "the one place Switchboard starts a browser")]
    let mut child = std::process::Command::new(&program)
        .args(&args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| LaunchError::Spawn(format!("{}: {e}.", program.display())))?;
    std::thread::spawn(move || child.wait());
    Ok(())
}

fn is_executable(path: &std::path::Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}
