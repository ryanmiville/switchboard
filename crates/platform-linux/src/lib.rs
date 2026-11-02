//! Switchboard's platform traits on Linux. Browsers are found through XDG desktop entries.

pub mod browsers;
pub mod fixture;

pub use browsers::LinuxBrowsers;
use switchboard_core::{Env, Home};

/// Browsers in `~/.local/share/applications` and each `$XDG_DATA_DIRS/applications`
/// (`/usr/local/share` and `/usr/share` when unset), the first entry for an id winning.
/// Or only the folders in `$SWITCHBOARD_RS_APPLICATIONS` when it is set.
pub fn browsers(home: &Home, env: &Env) -> LinuxBrowsers {
    if let Some(dirs) = &env.app_dirs {
        return LinuxBrowsers::new(home.clone(), dirs.clone(), env.path.clone());
    }
    let mut dirs = vec![home.join(".local/share/applications")];
    let data = if env.xdg_data_dirs.is_empty() {
        vec!["/usr/local/share".into(), "/usr/share".into()]
    } else {
        env.xdg_data_dirs.clone()
    };
    dirs.extend(data.into_iter().map(|d| d.join("applications")));
    LinuxBrowsers::new(home.clone(), dirs, env.path.clone())
}
