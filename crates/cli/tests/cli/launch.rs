//! Launching through the platform's real browser discovery and a real process. The fixture
//! browser's program records its arguments.

use switchboard_core::platform::recorded_launches;
use switchboard_core::{Destination, Env, launch};

use super::support::{Fixture, platform};

fn browsers(f: &Fixture) -> impl switchboard_core::Browsers {
    let env = Env { app_dirs: Some(vec![f.apps()]), ..Env::default() };
    platform::browsers(&f.home, &env)
}

fn wait_for_launches(f: &Fixture, count: usize) -> Vec<Vec<String>> {
    for _ in 0..200 {
        let launches = recorded_launches(&f.launches);
        if launches.len() >= count {
            return launches;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    recorded_launches(&f.launches)
}

#[test]
fn a_launch_passes_the_profile_directory_and_the_link_exactly_as_received() {
    let f = Fixture::new();
    let link = "https://EXAMPLE.com/Path/%7Euser?q=a%20b#frag";
    let destination = Destination { browser: f.chrome.clone(), profile: "Profile 3".into() };
    launch::launch(link, &destination, &browsers(&f)).unwrap();
    assert_eq!(wait_for_launches(&f, 1), [vec!["--profile-directory=Profile 3".to_owned(), link.to_owned()]]);
}

#[test]
fn a_legacy_display_name_launches_its_directory_in_its_own_browser() {
    let f = Fixture::new();
    let destination = Destination { browser: f.helium.clone(), profile: "Work".into() };
    launch::launch("https://a.com", &destination, &browsers(&f)).unwrap();
    assert_eq!(wait_for_launches(&f, 1)[0][0], "--profile-directory=Profile 1");
}

#[test]
fn launching_refuses_bad_links_and_unknown_profiles_without_starting_anything() {
    let f = Fixture::new();
    let b = browsers(&f);
    let chrome = |profile: &str| Destination { browser: f.chrome.clone(), profile: profile.into() };
    assert_eq!(
        launch::launch("javascript:alert(1)", &chrome("Default"), &b),
        Err(launch::LaunchError::InvalidUrl)
    );
    assert!(matches!(
        launch::launch("https://a.com", &chrome("Work"), &b),
        Err(launch::LaunchError::Profile(_))
    ));
    let gone = Destination {
        browser: f.home.join("Nope.app").to_string_lossy().into_owned(),
        profile: "Default".into(),
    };
    assert!(launch::launch("https://a.com", &gone, &b).is_err());
    std::thread::sleep(std::time::Duration::from_millis(50));
    assert!(recorded_launches(&f.launches).is_empty());
}
