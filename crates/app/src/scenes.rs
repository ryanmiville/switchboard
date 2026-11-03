//! Named starting states for headless renders (`--snap --scene <name>`), tests and goldens. Each
//! starts from [`crate::fixture::ui`]. Add a scene for every new pane or state, and list the
//! important ones in AGENTS.md.

use switchboard_core::config::Rule;

use crate::ui::{Draft, Failure, Open, Pane, Ui};

pub type Scene = (&'static str, fn(&mut Ui));

pub const SCENES: &[Scene] = &[
    ("general", |_| {}),
    ("login-approval", |ui| {
        ui.login = crate::login::Login::shown(switchboard_core::platform::LoginStatus::RequiresApproval)
    }),
    ("unfocused", |ui| ui.focused = false),
    ("general-menu", |ui| ui.open = Some(Open::DefaultBrowser)),
    ("no-default-browser", |ui| {
        ui.editor.edit(|c| c.browser.clear());
        ui.editor.flush();
        ui.editor.refresh_profiles();
    }),
    ("routing", |ui| ui.pane = Pane::Routing),
    ("routing-selected", |ui| {
        ui.pane = Pane::Routing;
        ui.selected = Some(ui.editor.config.rules[1].id);
    }),
    ("routing-dragging", |ui| {
        ui.pane = Pane::Routing;
        ui.selected = Some(ui.editor.config.rules[0].id);
        ui.drag = Some(crate::ui::RuleDrag { from: 0, to: 2, dy: 2.2 * crate::ui::routing::ROW_H });
    }),
    ("routing-test", |ui| {
        ui.pane = Pane::Routing;
        ui.test_url = rune::TextEdit::new("https://github.com/acme/api");
    }),
    ("routing-empty", |ui| {
        ui.pane = Pane::Routing;
        ui.editor.edit(|c| c.rules.clear());
        ui.editor.flush();
    }),
    ("missing-profile", |ui| {
        ui.pane = Pane::Routing;
        ui.editor.edit(|c| c.rules[0].profile = "Profile 9".into());
        ui.editor.refresh_profiles();
    }),
    ("rule-new", |ui| {
        ui.pane = Pane::Routing;
        ui.draft = Some(Draft::new_rule());
    }),
    ("rule-edit", |ui| {
        ui.pane = Pane::Routing;
        let rule: Rule = ui.editor.config.rules[1].clone();
        ui.draft = Some(Draft::editing(&rule));
    }),
    ("rule-browser-menu", |ui| {
        ui.pane = Pane::Routing;
        let rule: Rule = ui.editor.config.rules[1].clone();
        ui.draft = Some(Draft::editing(&rule));
        ui.open = Some(Open::DraftBrowser);
    }),
    ("rule-error", |ui| {
        ui.pane = Pane::Routing;
        let mut draft = Draft::new_rule();
        draft.value = rune::TextEdit::new("github.com/acme");
        draft.error = Some("“github.com/acme” isn't a domain. Domain rules take a host such as github.com, which also matches its subdomains.".into());
        ui.draft = Some(draft);
    }),
    ("conflict", |ui| {
        ui.editor.select_default_profile("Profile 1");
        std::fs::write(&ui.editor.store.path, ui.editor.config.encode()).ok();
        std::fs::write(&ui.editor.store.path, b"{\"browser\":\"x\",\"defaultProfile\":\"Default\"}\n").ok();
        ui.editor.check_external();
    }),
    ("load-error", |ui| {
        std::fs::write(&ui.editor.store.path, b"{\"browser\": ").ok();
        ui.editor.reload();
    }),
    ("link-failure", |ui| {
        ui.pane = Pane::Routing;
        ui.failure = Some(Failure {
            url: "https://github.com/acme/api/pull/12".into(),
            reason: "The profile “Profile 9” is unavailable. Choose an existing profile.".into(),
        });
    }),
    ("quick-switch", |ui| ui.pane = Pane::QuickSwitch),
];

/// The Quick Switch panel's scenes: `--window picker --scene <name>`.
pub type PickerScene = (&'static str, fn(&mut crate::picker::Picker));

pub const PICKER_SCENES: &[PickerScene] = &[
    ("picker", |_| {}),
    ("picker-permission", |p| {
        p.link = rune::TextEdit::new("");
        p.tab_read(Err(switchboard_core::platform::TabError::AutomationDenied));
    }),
    ("picker-unavailable-favorite", |p| {
        let mut settings = p.settings.clone();
        let browser = settings.favorites[0].browser.clone();
        settings.favorites.push(switchboard_core::picker::Favorite {
            browser,
            profile: "Profile 9".into(),
            name: "Old work".into(),
        });
        p.settings = settings.clone();
        p.all = crate::picker::choices(&p.browsers.installed(), &settings);
    }),
    ("picker-empty", |p| {
        p.settings.destinations = Some(Vec::new());
    }),
];
