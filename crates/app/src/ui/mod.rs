//! The settings window: a sidebar of panes (General, Routing, Quick Switch), the rule editor
//! sheet, and a notice when a link couldn't be opened.

pub mod controls;
mod general;
pub mod icons;
pub mod picker;
mod quick_switch;
pub mod routing;

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

/// Registers a global shortcut with the system.
pub type RegisterShortcut = Box<dyn Fn(&rune::Shortcut) -> Result<(), rune::ShortcutError>>;

/// A rule row being dragged: where it started, where it would land, and how far the pointer moved.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RuleDrag {
    pub from: usize,
    pub to: usize,
    pub dy: f32,
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
    pub login: crate::login::Login,
    /// The real login item, until `setup` starts its worker with the app's waker.
    pub login_item: Option<Box<dyn switchboard_core::platform::LoginItem>>,
    /// Whether the window has focus. The sidebar's edge brightens while it does, as macOS's own
    /// windows show which window is active.
    pub focused: bool,
    /// The selected rule in the Routing table.
    pub selected: Option<RuleId>,
    /// A rule being dragged to a new place.
    pub drag: Option<RuleDrag>,
    /// Routing's "Test a URL" field.
    pub test_url: rune::TextEdit,
    /// Browser icons, decoded off the main thread. Created in `setup` with the app's waker.
    pub icons: Option<icons::Icons>,
    /// The Quick Switch shortcut's recorder.
    pub recorder: rune_kit::ShortcutRecorderState,
    /// Registers a new global shortcut, replacing the old one. `None` in headless runs and tests,
    /// where a recorded shortcut is only saved.
    pub register_shortcut: Option<RegisterShortcut>,
    /// Scenes and tests own their temporary home; it is removed with the state.
    pub fixture: Option<tempfile::TempDir>,
}

impl Ui {
    pub fn new(editor: Editor) -> Ui {
        let shortcut = editor.config.picker.clone().unwrap_or_default().shortcut;
        Ui {
            focused: true,
            selected: None,
            drag: None,
            test_url: rune::TextEdit::new(""),
            icons: None,
            recorder: rune_kit::ShortcutRecorderState::new(shortcut.as_str().parse().ok()),
            register_shortcut: None,
            editor,
            pane: Pane::General,
            open: None,
            draft: None,
            failure: None,
            session: Session::default(),
            quit_at: None,
            now: 0.0,
            login: crate::login::Login::shown(switchboard_core::platform::LoginStatus::Disabled),
            login_item: None,
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
        let login = self.login.drain();
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
        login || before != (self.editor.has_unsaved_changes(), self.editor.error().map(str::to_owned))
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

    /// A newly recorded Quick Switch shortcut: registered first, so a chord the system refuses
    /// is never saved.
    pub fn record_shortcut(&mut self, shortcut: Option<&rune::Shortcut>) -> Result<(), rune::ShortcutError> {
        let Some(shortcut) = shortcut else {
            return Err(rune::ShortcutError::InvalidAccelerator("Quick Switch needs a shortcut".into()));
        };
        if let Some(register) = &self.register_shortcut {
            register(shortcut)?;
        }
        let text = shortcut.to_string();
        self.editor.edit(|c| {
            let mut picker = c.picker.clone().unwrap_or_default();
            picker.shortcut = switchboard_core::picker::Shortcut::new(text);
            c.picker = Some(picker);
        });
        Ok(())
    }

    /// The selected rule's index.
    pub fn selected_index(&self) -> Option<usize> {
        self.selected.and_then(|id| self.editor.config.index_of(id))
    }

    pub fn edit_selected(&mut self, tx: &mut Tx) {
        let Some(i) = self.selected_index() else { return };
        tx.instant();
        self.open = None;
        self.draft = Some(Draft::editing(&self.editor.config.rules[i]));
    }

    /// Removes the selected rule and selects the one that took its place.
    pub fn delete_selected(&mut self) {
        let Some(i) = self.selected_index() else { return };
        let id = self.editor.config.rules[i].id;
        self.editor.delete_rule(id);
        let rules = &self.editor.config.rules;
        self.selected = rules.get(i).or(rules.last()).map(|r| r.id);
    }

    /// Routing's keys, when nothing is open: arrows move the selection, Return edits, Delete and
    /// Backspace remove.
    fn routing_key(&mut self, ev: &KeyEvent, tx: &mut Tx) -> bool {
        if self.pane != Pane::Routing || self.draft.is_some() || self.open.is_some() {
            return false;
        }
        let count = self.editor.config.rules.len();
        if count == 0 {
            return false;
        }
        let at = self.selected_index();
        let pick = |i: usize| Some(self.editor.config.rules[i].id);
        match ev.key {
            Key::Down => self.selected = pick(at.map_or(0, |i| (i + 1).min(count - 1))),
            Key::Up => self.selected = pick(at.map_or(count - 1, |i| i.saturating_sub(1))),
            Key::Enter => self.edit_selected(tx),
            Key::Backspace | Key::Delete => self.delete_selected(),
            _ => return false,
        }
        tx.instant();
        true
    }

    /// Escape closes the innermost open thing.
    pub fn on_key(&mut self, ev: &KeyEvent, tx: &mut Tx) -> bool {
        if ev.key != Key::Escape {
            return self.routing_key(ev, tx);
        }
        if self.drag.take().is_some() {
            return true;
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
        ui.focused = focused;
        // The CLI may have changed the file while the window was in the background.
        if focused {
            ui.editor.check_external();
            ui.login.refresh();
        }
    })
}

/// The window's frame on macOS: content under a transparent title bar, the traffic lights inside
/// the sidebar's top-left corner, and only `.window_drag()` areas moving the window.
pub const CHROME: rune::Chrome = rune::Chrome {
    full_size_content: true,
    traffic_lights: Some((SIDEBAR_INSET + 14.0, SIDEBAR_INSET + 14.0)),
    drag_regions: true,
};

/// How far the sidebar panel sits in from the window's edges.
const SIDEBAR_INSET: f32 = 8.0;
const SIDEBAR_W: f32 = 200.0;

/// The sidebar: a rounded panel inset from the window, as macOS's own settings windows draw it.
/// Its empty space drags the window.
fn sidebar(ui: &Ui, p: Paint) -> El {
    let mut list = col()
        .key("sidebar")
        .w(SIDEBAR_W)
        .h_full()
        .pt(52.0)
        .px(8.0)
        .gap(2.0)
        .radius(p.k.radius.xl)
        .fill(p.k.c.bg_base)
        // The edge lights up while the window is the active one.
        // (The neutral kit's strong border is its separator colour, too faint for this.)
        .border(1.0, if ui.focused { p.k.c.text_base.alpha(0.2) } else { p.k.c.border_muted })
        .window_drag();
    for shadow in &p.k.elevation.raised {
        list = list.box_shadow(*shadow);
    }
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
    col().key("sidebar-inset").h_full().padding(SIDEBAR_INSET).pr(0.0).child(list)
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
        .window_drag()
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
