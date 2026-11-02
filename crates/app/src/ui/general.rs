//! General: the default destination and history.

use rune::El;
use switchboard_core::platform::LoginStatus;

use super::controls::{
    Choice, Kind, Paint, button, note, page, scroll_body, section, select, setting_row, toggle_row,
};
use super::{Open, Ui};

pub fn pane(ui: &Ui, p: Paint, layer: &mut Vec<El>) -> El {
    let e = &ui.editor;
    let c = &e.config;

    let browsers: Vec<Choice> = e
        .installed
        .iter()
        .map(|b| {
            let locator = b.locator.clone();
            Choice::new(
                b.name.clone(),
                e.browsers.standardize(&c.browser) == b.locator,
                move |ui: &mut Ui| ui.editor.select_default_browser(&locator),
            )
        })
        .collect();
    let browser = select(p, Open::DefaultBrowser, &e.browser_name(&c.browser), ui.open, browsers, layer);

    let profiles: Vec<Choice> = e
        .profiles_of(&c.browser)
        .into_iter()
        .map(|pr| {
            let dir = pr.directory.clone();
            let label = if pr.name == pr.directory {
                pr.name.clone()
            } else {
                format!("{} ({})", pr.name, pr.directory)
            };
            Choice::new(label, c.default_profile == pr.directory, move |ui: &mut Ui| {
                ui.editor.select_default_profile(&dir)
            })
        })
        .collect();
    let profile = select(
        p,
        Open::DefaultProfile,
        &e.profile_name(&c.browser, &c.default_profile),
        ui.open,
        profiles,
        layer,
    );

    let mut destination = vec![
        setting_row(p, "default-browser-row", "Browser", Some("Links that match no rule open here"), browser),
        setting_row(p, "default-profile-row", "Profile", None, profile),
    ];
    if let Some(error) = &e.profile_error {
        destination.push(note("profile-error", error, p.danger()));
    }

    let history_on = c.history_enabled();
    let mut history = vec![
        toggle_row(
            p,
            "history-toggle",
            "Keep a history of opened links",
            Some("So you and your agents can ask why a link opened where it did"),
            history_on,
            move |ui: &mut Ui| ui.editor.set_history_enabled(!history_on),
        ),
        setting_row(
            p,
            "clear-history-row",
            "Clear history",
            None,
            button(p, "clear-history", "Clear", Kind::Secondary, |ui: &mut Ui, _| ui.editor.clear_history()),
        ),
    ];
    if let Some(error) = &e.history_error {
        history.push(note("history-error", error, p.danger()));
    }

    let mut startup = Vec::new();
    let on = matches!(ui.login.status, Some(LoginStatus::Enabled | LoginStatus::RequiresApproval));
    let description = match ui.login.status {
        Some(LoginStatus::RequiresApproval) => "Waiting for you to allow it in System Settings → Login Items",
        None => "Checking…",
        _ => "Keeps the menu-bar icon and Quick Switch ready",
    };
    startup.push(toggle_row(
        p,
        "login-toggle",
        "Open at login",
        Some(description),
        on,
        move |ui: &mut Ui| ui.login.set_enabled(!on),
    ));
    if ui.login.status == Some(LoginStatus::RequiresApproval) {
        startup.push(setting_row(
            p,
            "login-settings-row",
            "Login Items",
            None,
            button(p, "login-settings", "Open System Settings", Kind::Secondary, |ui: &mut Ui, _| {
                ui.login.open_settings()
            }),
        ));
    }
    if let Some(error) = &ui.login.error {
        startup.push(note("login-error", error, p.danger()));
    }

    let path = e
        .store
        .path
        .strip_prefix(e.home.path())
        .map_or_else(|_| e.store.path.display().to_string(), |rel| format!("~/{}", rel.display()));
    let file = vec![setting_row(
        p,
        "config-path-row",
        "Settings file",
        Some("switchboard-rs reads and changes the same file"),
        rune::text(path).key("config-path").font(super::controls::DESCRIPTION).color(p.muted()),
    )];

    scroll_body(
        "general",
        page("general-page")
            .child(section(p, "destination", "Default destination", destination))
            .child(section(p, "startup", "Startup", startup))
            .child(section(p, "history", "History", history))
            .child(section(p, "file", "Configuration", file)),
    )
}
