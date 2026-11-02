//! Launch at login through an XDG autostart entry: `~/.config/autostart/switchboard-rs.desktop`
//! (or under `$XDG_CONFIG_HOME`), which desktop sessions run when the person logs in.

use std::path::PathBuf;

use switchboard_core::identity;
use switchboard_core::platform::{LoginItem, LoginStatus};

pub struct Autostart {
    /// The autostart entry.
    pub entry: PathBuf,
    /// The program the entry starts: the app binary.
    pub program: PathBuf,
}

impl Autostart {
    pub fn new(config_home: PathBuf, program: PathBuf) -> Autostart {
        Autostart {
            entry: config_home.join("autostart").join(format!("{}.desktop", identity::CLI_NAME)),
            program,
        }
    }

    fn contents(&self) -> String {
        format!(
            "[Desktop Entry]\nType=Application\nName={}\nExec=\"{}\"\nX-GNOME-Autostart-enabled=true\n",
            identity::APP_NAME,
            self.program.display()
        )
    }
}

impl LoginItem for Autostart {
    fn status(&self) -> Result<LoginStatus, String> {
        Ok(if self.entry.is_file() { LoginStatus::Enabled } else { LoginStatus::Disabled })
    }

    fn set_enabled(&self, enabled: bool) -> Result<LoginStatus, String> {
        let fail = |e: std::io::Error| format!("{}: {e}", self.entry.display());
        if enabled {
            if let Some(dir) = self.entry.parent() {
                std::fs::create_dir_all(dir).map_err(fail)?;
            }
            std::fs::write(&self.entry, self.contents()).map_err(fail)?;
        } else if self.entry.exists() {
            std::fs::remove_file(&self.entry).map_err(fail)?;
        }
        self.status()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enabling_writes_an_autostart_entry_for_the_app_and_disabling_removes_it() {
        let dir = tempfile::tempdir().unwrap();
        let item = Autostart::new(dir.path().join(".config"), "/opt/sb/switchboard-rs-app".into());
        assert_eq!(item.status(), Ok(LoginStatus::Disabled));
        assert_eq!(item.set_enabled(true), Ok(LoginStatus::Enabled));
        let text = std::fs::read_to_string(&item.entry).unwrap();
        assert!(text.contains("Exec=\"/opt/sb/switchboard-rs-app\""), "{text}");
        assert_eq!(item.set_enabled(false), Ok(LoginStatus::Disabled));
        assert!(!item.entry.exists());
        assert_eq!(item.set_enabled(false), Ok(LoginStatus::Disabled), "turning off twice is fine");
    }
}
