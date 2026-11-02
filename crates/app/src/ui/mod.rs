//! The settings window: a sidebar of panes (General, Routing, Quick Switch), the rule editor
//! sheet, and a notice when a link couldn't be opened.

pub mod controls;
mod general;
mod quick_switch;
mod routing;

use std::sync::OnceLock;

use rune::{Cx, El, Key, KeyEvent, Tx, col, el, row, text};
use rune_kit::Kit;
use switchboard_core::config::{Condition, Rule, RuleId};

use crate::editor::Editor;
use crate::routing::Session;
use controls::{Kind, METRICS, Paint, button};

/// The kit for each appearance, built once.
pub fn kit(dark: bool) -> &'static Kit {
    static KITS: OnceLock<(Kit, Kit)> = OnceLock::new();
    let (light, darkk) = KITS.get_or_init(|| (Kit::neutral(false), Kit::neutral(true)));
    if dark { darkk } else { light }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Pane {
    General,
    Routing,
    QuickSwitch,
}

impl Pane {
    pub const ALL: [Pane; 3] = [Pane::General, Pane::Routing, Pane::QuickSwitch];

    pub fn title(self) -> &'static str {
        match self {
            Pane::General => "General",
            Pane::Routing => "Routing",
            Pane::QuickSwitch => "Quick Switch",
        }
    }

    fn key(self) -> &'static str {
        match self {
            Pane::General => "nav-general",
            Pane::Routing => "nav-routing",
            Pane::QuickSwitch => "nav-quick-switch",
        }
    }
}

/// The one menu that can be open.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Open {
    DefaultBrowser,
    DefaultProfile,
    DraftCondition,
    DraftBrowser,
    DraftProfile,
}

impl Open {
    pub fn key(self) -> &'static str {
        match self {
            Open::DefaultBrowser => "default-browser",
            Open::DefaultProfile => "default-profile",
            Open::DraftCondition => "draft-condition",
            Open::DraftBrowser => "draft-browser",
            Open::DraftProfile => "draft-profile",
        }
    }
}

/// A rule being added or edited. Only Done changes the config.
pub struct Draft {
    pub id: RuleId,
    pub is_new: bool,
    pub condition: Condition,
    pub value: rune::TextEdit,
    /// `None` inherits the default browser.
    pub browser: Option<String>,
    pub profile: String,
    pub error: Option<String>,
}

impl Draft {
    pub fn new_rule() -> Draft {
        Draft {
            id: RuleId::default(),
            is_new: true,
            condition: Condition::Domain,
            value: rune::TextEdit::new(""),
            browser: None,
            profile: String::new(),
            error: None,
        }
    }

    pub fn editing(rule: &Rule) -> Draft {
        Draft {
            id: rule.id,
            is_new: false,
            condition: rule.condition,
            value: rune::TextEdit::new(rule.value.clone()),
            browser: rule.browser.clone(),
            profile: rule.profile.clone(),
            error: None,
        }
    }

    /// Changing the browser needs a new profile: directory names belong to one browser.
    pub fn select_browser(&mut self, browser: Option<String>, default_browser: &str) {
        let old = self.browser.as_deref().unwrap_or(default_browser);
        if browser.as_deref().unwrap_or(default_browser) != old {
            self.profile.clear();
        }
        self.browser = browser;
    }
}

/// A link that couldn't be opened, and why.
#[derive(Clone, Debug)]
pub struct Failure {
    pub url: String,
    pub reason: String,
}

pub struct Ui {
    pub editor: Editor,
    pub pane: Pane,
    pub open: Option<Open>,
    pub draft: Option<Draft>,
    pub failure: Option<Failure>,
    pub session: Session,
    /// A link-only launch quits at this app-clock time, if its ticket is still the latest.
    pub quit_at: Option<(u64, f64)>,
    /// The app clock at the last poll.
    pub now: f64,
    /// Scenes and tests own their temporary home; it is removed with the state.
    pub fixture: Option<tempfile::TempDir>,
}

impl Ui {
    pub fn new(editor: Editor) -> Ui {
        Ui {
            editor,
            pane: Pane::General,
            open: None,
            draft: None,
            failure: None,
            session: Session::default(),
            quit_at: None,
            now: 0.0,
            fixture: None,
        }
    }

    /// Navigation is instant: the person's hand caused it.
    pub fn go(&mut self, pane: Pane, tx: &mut Tx) {
        tx.instant();
        self.pane = pane;
        self.open = None;
    }

    pub fn poll(&mut self, now: f64, tx: &mut Tx) -> bool {
        self.now = now;
        let before = (self.editor.has_unsaved_changes(), self.editor.error().map(str::to_owned));
        if let Some(wait) = self.editor.poll(now) {
            tx.wake_after(wait);
        }
        if let Some((ticket, at)) = self.quit_at {
            if now >= at {
                self.quit_at = None;
                if self.session.should_quit_after(ticket) && self.failure.is_none() {
                    tx.quit();
                }
            } else {
                tx.wake_after(std::time::Duration::from_secs_f64(at - now));
            }
        }
        before != (self.editor.has_unsaved_changes(), self.editor.error().map(str::to_owned))
    }

    /// A link from the system. Pending edits are saved first, so routing uses what the person sees.
    /// A failure stays on screen with recovery actions instead of opening somewhere else.
    pub fn receive_link(&mut self, link: &str, now: switchboard_core::time::Timestamp, tx: &mut Tx) {
        let ticket = self.session.receive_link();
        self.editor.check_external();
        let result = if !(switchboard_core::url::is_web(link) || switchboard_core::url::is_local_file(link)) {
            Err("Switchboard can only open complete HTTP or HTTPS links and local files.".to_owned())
        } else if self.editor.flush() {
            let e = &self.editor;
            crate::routing::open(link, &e.config, e.browsers.as_ref(), &e.history, now)
        } else {
            Err(self.editor.error().unwrap_or("Your settings couldn't be saved.").to_owned())
        };
        match result {
            Ok(()) => {
                self.quit_at = Some((ticket, self.now + crate::routing::IDLE_EXIT));
                tx.wake_after(std::time::Duration::from_secs_f64(crate::routing::IDLE_EXIT));
            }
            Err(reason) => {
                self.session.stay_resident();
                self.failure = Some(Failure { url: link.to_owned(), reason });
            }
        }
    }

    /// Escape closes the innermost open thing.
    pub fn on_key(&mut self, ev: &KeyEvent, tx: &mut Tx) -> bool {
        if ev.key != Key::Escape {
            return false;
        }
        tx.instant();
        if self.open.take().is_some() {
            return true;
        }
        if self.draft.take().is_some() {
            return true;
        }
        self.failure.take().is_some()
    }
}

pub fn view(ui: &Ui, cx: &mut Cx<Ui>) -> El {
    let p = Paint::new(cx.system_dark(), cx.env().scale);
    let mut layer = Vec::new();
    let body = match ui.pane {
        Pane::General => general::pane(ui, p, &mut layer),
        Pane::Routing => routing::pane(ui, p, &mut layer),
        Pane::QuickSwitch => quick_switch::pane(ui, p, &mut layer),
    };
    let mut panel = col()
        .key("panel")
        .grow(1.0)
        .shrink()
        .min_w(0.0)
        .h_full()
        .fill(p.k.c.bg_deep)
        .child(header(ui, p))
        .children(notices(ui, p))
        .child(body.key(format!("pane-{}", ui.pane.key())));
    if ui.editor.has_unsaved_changes() {
        panel = panel.label("Unsaved changes");
    }
    let window = row().key("window").w_full().h_full().fill(p.k.c.bg_deep).child(sidebar(ui, p)).child(panel);
    routing::sheet(ui, p, &mut layer);
    rune_kit::root(window, layer).on_window_focus(|ui: &mut Ui, focused, _| {
        // The CLI may have changed the file while the window was in the background.
        if focused {
            ui.editor.check_external();
        }
    })
}

fn sidebar(ui: &Ui, p: Paint) -> El {
    let mut list = col().key("sidebar").w(190.0).h_full().pt(48.0).px(10.0).gap(2.0).fill(p.k.c.layer_01);
    for pane in Pane::ALL {
        let selected = ui.pane == pane;
        let item = row()
            .key(pane.key())
            .role("tab")
            .label(pane.title())
            .w_full()
            .h(30.0)
            .px(10.0)
            .center_y()
            .radius(p.k.radius.md)
            .fill(if selected { p.k.c.layer_03 } else { rune::Color::TRANSPARENT })
            .hover(p.k.c.hover)
            .focusable(true)
            .on_press_tx(move |ui: &mut Ui, tx| ui.go(pane, tx))
            .child(
                text(pane.title())
                    .key("title")
                    .font(if selected { p.k.ty.ui_medium } else { p.k.ty.ui })
                    .color(if selected { p.text() } else { p.muted() }),
            );
        list = list.child(item);
    }
    list
}

fn header(ui: &Ui, p: Paint) -> El {
    let e = &ui.editor;
    let status =
        match (e.has_unsaved_changes(), e.conflict || e.save_error.is_some() || e.profile_error.is_some()) {
            (true, true) => "Not saved",
            (true, false) => "Saving…",
            (false, _) => "",
        };
    row()
        .key("pane-header")
        .w_full()
        .h(52.0)
        .px(METRICS.gutter)
        .center_y()
        .gap(8.0)
        .child(text(ui.pane.title()).key("pane-title").font(p.k.ty.body_medium).color(p.text()))
        .child(el().key("header-spacer").grow(1.0))
        .child(text(status).key("save-status").font(controls::DESCRIPTION).color(p.muted()))
}

/// Problems that need the person: a link that didn't open, a file that can't be read or saved.
fn notices(ui: &Ui, p: Paint) -> Vec<El> {
    let mut out = Vec::new();
    let wrap = |e: El| col().key("notices").w_full().px(METRICS.gutter - METRICS.row_px).pb(12.0).child(e);
    if let Some(f) = &ui.failure {
        let url = f.url.clone();
        out.push(wrap(controls::banner(
            p,
            "link-failure",
            "The link couldn't be opened",
            &format!("{} Fix the issue here, or copy the link to open it yourself.", f.reason),
            vec![
                button(p, "copy-link", "Copy link", Kind::Secondary, move |ui: &mut Ui, tx| {
                    tx.copy(url.clone());
                    ui.failure = None;
                }),
                button(p, "dismiss-failure", "Dismiss", Kind::Secondary, |ui: &mut Ui, _| ui.failure = None),
            ],
        )));
    }
    let e = &ui.editor;
    if let Some(error) = &e.load_error {
        out.push(wrap(controls::banner(
            p,
            "load-error",
            "Settings couldn't be read",
            error,
            vec![button(p, "reload", "Reload", Kind::Secondary, |ui: &mut Ui, _| ui.editor.reload())],
        )));
    } else if e.conflict {
        out.push(wrap(controls::banner(
            p,
            "conflict",
            "Settings changed elsewhere",
            e.save_error.as_deref().unwrap_or_default(),
            vec![
                button(p, "keep-mine", "Keep my changes", Kind::Secondary, |ui: &mut Ui, _| {
                    ui.editor.keep_mine();
                }),
                button(p, "use-saved", "Use saved settings", Kind::Secondary, |ui: &mut Ui, _| {
                    ui.editor.reload()
                }),
            ],
        )));
    } else if let Some(error) = &e.save_error {
        out.push(wrap(controls::banner(
            p,
            "save-error",
            "Changes couldn't be saved",
            error,
            vec![button(p, "retry-save", "Retry", Kind::Secondary, |ui: &mut Ui, _| {
                ui.editor.flush();
            })],
        )));
    }
    out
}
