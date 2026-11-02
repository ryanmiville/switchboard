//! Launch at login: the row, and the worker over the real Linux autostart entry in a temporary
//! home. (macOS's SMAppService needs the packaged app and a person; it is on the Mac checklist.)

use switchboard_core::platform::LoginStatus;

use super::support::{runtime, shows, tap};

#[test]
fn the_login_row_without_a_worker_only_changes_what_it_shows() {
    let mut rt = runtime("general");
    tap(&mut rt, "login-toggle");
    assert_eq!(rt.state.login.status, Some(LoginStatus::Enabled));
}

#[test]
fn waiting_for_approval_offers_the_system_settings_button() {
    let rt = runtime("login-approval");
    assert!(shows(&rt, "Waiting for you to allow it"));
    assert!(rt.elements().iter().any(|e| e.key.as_deref() == Some("login-settings")));
}

#[cfg(not(target_os = "macos"))]
#[test]
fn the_worker_turns_the_autostart_entry_on_and_off() {
    use switchboard_app::login::Login;
    let dir = tempfile::tempdir().unwrap();
    let item =
        switchboard_linux::Autostart::new(dir.path().join(".config"), "/opt/switchboard-rs-app".into());
    let entry = item.entry.clone();
    let mut login = Login::start(Box::new(item), std::sync::Arc::new(|| {}));
    let wait = |login: &mut Login, want: LoginStatus| {
        for _ in 0..200 {
            login.drain();
            if login.status == Some(want) {
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(5));
        }
        panic!("login status stayed {:?}, wanted {want:?}", login.status);
    };
    wait(&mut login, LoginStatus::Disabled);
    login.set_enabled(true);
    wait(&mut login, LoginStatus::Enabled);
    assert!(entry.exists());
    login.set_enabled(false);
    wait(&mut login, LoginStatus::Disabled);
    assert!(!entry.exists());
}
