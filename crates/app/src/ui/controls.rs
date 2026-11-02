//! The pieces every pane is built from: page, section, card, rows, selects, buttons, notes. Panes
//! compose these and nothing else. Colours, type, radii and shadows come from the kit.

use rune::{Color, El, ScrollSpec, TextStyle, Tx, col, el, row, text};
use rune_kit::{Button, ButtonVariant, Kit, Menu, MenuItem, Placement, Select, SelectAppearance, Switch};

use super::{Open, Ui};

/// A pane's measurements.
pub struct Metrics {
    /// The page's text edge.
    pub gutter: f32,
    pub section_gap: f32,
    /// From a section label to its card.
    pub label_gap: f32,
    /// A row's inset inside its card, and how far cards hang past the gutter.
    pub row_px: f32,
    pub row_h: f32,
    pub select_w: f32,
}

pub const METRICS: Metrics =
    Metrics { gutter: 28.0, section_gap: 24.0, label_gap: 8.0, row_px: 14.0, row_h: 46.0, select_w: 230.0 };

pub const DESCRIPTION: TextStyle = TextStyle::new(12.0, 440.0).lh(16.0);

/// Everything a piece needs to paint itself.
#[derive(Clone, Copy)]
pub struct Paint {
    pub k: &'static Kit,
    /// One device pixel, for hairlines.
    pub hair: f32,
}

impl Paint {
    pub fn new(dark: bool, scale: f32) -> Paint {
        Paint { k: super::kit(dark), hair: 1.0 / scale.max(1.0) }
    }
    pub fn text(self) -> Color {
        self.k.c.text_base
    }
    pub fn muted(self) -> Color {
        self.k.c.text_muted
    }
    pub fn danger(self) -> Color {
        self.k.c.danger.fg
    }
}

/// A scrolling pane body whose edges fade only while content is hidden under them.
pub fn scroll_body(key: &str, content: El) -> El {
    col()
        .key(key)
        .grow(1.0)
        .shrink()
        .min_h(0.0)
        .clip_fade(0.0, 4.0, 0.0, 24.0)
        .scroll(ScrollSpec { stick_bottom: false })
        .child(col().key("inset").w_full().pt(4.0).pb(24.0).child(content))
}

/// A pane's column of sections; cards hang past the gutter so row text lands on it.
pub fn page(key: &str) -> El {
    col().key(key).w_full().px(METRICS.gutter - METRICS.row_px).gap(METRICS.section_gap)
}

/// A titled card of rows, separated by hairlines.
pub fn section(p: Paint, key: &str, title: &str, rows: Vec<El>) -> El {
    col()
        .key(key)
        .w_full()
        .gap(METRICS.label_gap)
        .child(text(title).key("label").font(p.k.ty.small_medium).color(p.muted()).mx(METRICS.row_px))
        .child(card(p, "card", rows))
}

pub fn card(p: Paint, key: &str, rows: Vec<El>) -> El {
    let mut surface = col().key(key).w_full().fill(p.k.c.bg_base).radius(p.k.radius.lg);
    for shadow in &p.k.elevation.raised {
        surface = surface.box_shadow(*shadow);
    }
    for (i, r) in rows.into_iter().enumerate() {
        if i > 0 {
            surface = surface.child(
                el().key(format!("sep{}", i - 1)).h(p.hair).mx(METRICS.row_px).fill(p.k.c.border_muted),
            );
        }
        surface = surface.child(r);
    }
    surface
}

/// Title and an optional description on the left, a control on the right.
pub fn setting_row(p: Paint, key: &str, title: &str, description: Option<&str>, control: El) -> El {
    let mut copy = col()
        .key("copy")
        .grow(1.0)
        .shrink()
        .min_w(120.0)
        .gap(2.0)
        .child(text(title).key("title").font(p.k.ty.ui).color(p.text()));
    if let Some(d) = description {
        copy = copy.child(text(d).key("description").font(DESCRIPTION).color(p.muted()).wrap().w_full());
    }
    row()
        .key(key.to_owned())
        .label(title)
        .w_full()
        .min_h(METRICS.row_h)
        .px(METRICS.row_px)
        .py(8.0)
        .gap(16.0)
        .center_y()
        .child(copy)
        .child(control)
}

/// A row that toggles when pressed anywhere; its switch only shows the state.
pub fn toggle_row(
    p: Paint,
    key: &str,
    title: &str,
    description: Option<&str>,
    on: bool,
    flip: impl Fn(&mut Ui) + 'static,
) -> El {
    let switch = Switch::new(on).build(p.k).key("switch").focusable(false);
    setting_row(p, key, title, description, switch).role("toggle").focusable(true).on_press(flip)
}

/// One choice in a [`select`].
pub struct Choice {
    pub label: String,
    pub selected: bool,
    pub choose: Box<dyn Fn(&mut Ui)>,
}

impl Choice {
    pub fn new(label: impl Into<String>, selected: bool, choose: impl Fn(&mut Ui) + 'static) -> Choice {
        Choice { label: label.into(), selected, choose: Box::new(choose) }
    }
}

/// A field that opens a menu of choices. Only one menu is open at a time ([`Ui::open`]).
pub fn select(
    p: Paint,
    which: Open,
    current: &str,
    open: Option<Open>,
    choices: Vec<Choice>,
    layer: &mut Vec<El>,
) -> El {
    let key = which.key();
    let is_open = open == Some(which);
    let trigger = Select::new::<&str>(format!("{key}-field"), &[])
        .appearance(SelectAppearance::Field)
        .width(METRICS.select_w)
        .current(Some(current))
        .open(is_open)
        .on_toggle(move |ui: &mut Ui| ui.open = if ui.open == Some(which) { None } else { Some(which) })
        .trigger(p.k);
    let mut menu = Menu::new(key)
        .trigger(trigger)
        .placement(Placement::BottomEnd)
        .gutter(4.0)
        .min_width(METRICS.select_w)
        .open(is_open)
        .on_close(|ui: &mut Ui| ui.open = None);
    for choice in choices {
        let choose = std::rc::Rc::new(choice.choose);
        menu =
            menu.item(MenuItem::new(choice.label).checked(choice.selected).on_select(move |ui: &mut Ui| {
                ui.open = None;
                choose(ui);
            }));
    }
    menu.build(p.k, layer)
}

#[derive(Clone, Copy)]
pub enum Kind {
    Primary,
    Secondary,
    Danger,
}

pub fn button(
    p: Paint,
    key: &str,
    label: &str,
    kind: Kind,
    press: impl Fn(&mut Ui, &mut Tx) + 'static,
) -> El {
    let variant = match kind {
        Kind::Primary => ButtonVariant::Contrast,
        Kind::Secondary => ButtonVariant::Neutral,
        Kind::Danger => ButtonVariant::Danger,
    };
    Button::new(label).variant(variant).on_press_tx(press).build(p.k).key(key)
}

/// A line of secondary copy on the gutter, such as an explanation or an error.
pub fn note(key: &str, copy: &str, color: Color) -> El {
    row()
        .key(key)
        .w_full()
        .px(METRICS.row_px)
        .child(text(copy).key("copy").font(DESCRIPTION).color(color).wrap().grow(1.0))
}

/// A notice above a pane: the problem and the buttons that fix it.
pub fn banner(p: Paint, key: &str, title: &str, detail: &str, actions: Vec<El>) -> El {
    let mut surface = col()
        .key(key)
        .w_full()
        .gap(10.0)
        .padding(14.0)
        .radius(p.k.radius.lg)
        .fill(p.k.c.danger.bg)
        .border(p.hair, p.k.c.danger.border)
        .child(text(title).key("title").font(p.k.ty.ui_medium).color(p.text()))
        .child(text(detail).key("detail").font(DESCRIPTION).color(p.text()).wrap().w_full());
    if !actions.is_empty() {
        surface = surface.child(row().key("actions").gap(8.0).children(actions));
    }
    surface
}
