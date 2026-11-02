//! The Quick Switch panel's view. Functional for now: the look gets its own pass later.

use rune::{Cx, El, col, el, row, text};
use rune_kit::{Button, ButtonVariant, TextInput};

use super::controls::{DESCRIPTION, Paint};
use crate::picker::{Picker, ROW_H, WIDTH};

pub fn view(p: &Picker, cx: &mut Cx<Picker>) -> El {
    let paint = Paint::new(cx.system_dark(), cx.env().scale);
    let k = paint.k;
    let field = TextInput::new(&p.link)
        .placeholder("Paste an HTTP or HTTPS link")
        .on_edit(|p: &mut Picker| &mut p.link)
        .on_submit(|p: &mut Picker, tx| p.open(p.selected, tx))
        .width(None)
        .build(k)
        .key("link")
        .label("Link to open");

    let mut panel = col()
        .key("picker")
        .w(WIDTH)
        .padding(16.0)
        .gap(10.0)
        .radius(k.radius.xl)
        .fill(k.c.bg_base)
        .border(paint.hair, k.c.border_base)
        .child(text("Link to open").key("link-label").font(k.ty.small_medium).color(paint.muted()))
        .child(field);
    for shadow in &k.elevation.overlay {
        panel = panel.box_shadow(*shadow);
    }
    if let Some(error) = &p.error {
        let mut notice = col()
            .key("error")
            .gap(6.0)
            .child(text(error).key("message").font(DESCRIPTION).color(paint.danger()).wrap().w_full());
        if p.needs_permission {
            notice = notice.child(
                Button::new("Automation Settings…")
                    .variant(ButtonVariant::Neutral)
                    .on_press(|p: &mut Picker| p.tab.open_automation_settings())
                    .build(k)
                    .key("automation-settings"),
            );
        }
        panel = panel.child(notice);
    }
    panel = panel.child(text("Open in").key("open-in").font(k.ty.ui_medium).color(paint.text()));

    let shown = p.shown();
    let mut list = col().key("choices").w_full().gap(4.0);
    if shown.is_empty() {
        list = list.child(
            col()
                .key("empty")
                .gap(4.0)
                .py(8.0)
                .child(text("No destinations to show").key("title").font(k.ty.ui_medium).color(paint.text()))
                .child(
                    text("Choose the profiles you want in Quick Switch settings.")
                        .key("detail")
                        .font(DESCRIPTION)
                        .color(paint.muted()),
                ),
        );
    }
    let mut favorite = 0;
    for (i, c) in shown.iter().enumerate() {
        let number = c.favorite.then(|| {
            favorite += 1;
            favorite
        });
        let selected = i == p.selected;
        let mut copy = col()
            .key("copy")
            .grow(1.0)
            .shrink()
            .gap(2.0)
            .child(text(c.profile_name.clone()).key("profile").font(k.ty.ui_medium).color(paint.text()))
            .child(text(c.browser_name.clone()).key("browser").font(DESCRIPTION).color(paint.muted()));
        if let Some(error) = &c.error {
            copy = copy.child(
                text(error.clone()).key("error").font(DESCRIPTION).color(paint.danger()).wrap().w_full(),
            );
        }
        let hint = number.filter(|n| *n <= 9).map(|n| format!("⌘{n}")).unwrap_or_default();
        let star = Button::new(if c.favorite { "★" } else { "☆" })
            .variant(ButtonVariant::Ghost)
            .disabled(!c.favorite && c.error.is_some())
            .on_press(move |p: &mut Picker| p.toggle_favorite(i))
            .build(k)
            .key("star")
            .label(if c.favorite {
                format!("Remove favorite: {}", c.label())
            } else {
                format!("Add favorite: {}", c.label())
            });
        list = list.child(
            row()
                .key(format!("choice-{i}"))
                .role("button")
                .label(c.label())
                .w_full()
                .min_h(ROW_H - 4.0)
                .px(10.0)
                .py(6.0)
                .gap(10.0)
                .center_y()
                .radius(k.radius.md)
                .fill(if selected { k.c.layer_03 } else { k.c.layer_01 })
                .hover(k.c.hover)
                .on_press_tx(move |p: &mut Picker, tx| p.open(i, tx))
                .child(copy)
                .child(text(hint).key("hint").font(k.ty.mono).color(paint.muted()))
                .child(star),
        );
    }
    let list = col()
        .key("choices-scroll")
        .w_full()
        .max_h(6.0 * ROW_H)
        .min_h(0.0)
        .clip_fade(0.0, 0.0, 0.0, 12.0)
        .scroll(rune::ScrollSpec { stick_bottom: false })
        .child(list);
    panel = panel
        .child(list)
        .child(
            text("Opens a new tab. The original tab stays open.")
                .key("note")
                .font(DESCRIPTION)
                .color(paint.muted()),
        )
        .child(
            row()
                .key("footer")
                .w_full()
                .gap(8.0)
                .child(
                    Button::new("Settings…")
                        .variant(ButtonVariant::Neutral)
                        .on_press_tx(|p: &mut Picker, tx| p.open_settings(tx))
                        .build(k)
                        .key("picker-settings"),
                )
                .child(
                    Button::new("Refresh")
                        .variant(ButtonVariant::Neutral)
                        .on_press(|p: &mut Picker| p.refresh())
                        .build(k)
                        .key("refresh"),
                )
                .child(el().key("spacer").grow(1.0))
                .child(
                    Button::new("Cancel")
                        .variant(ButtonVariant::Neutral)
                        .on_press_tx(|_: &mut Picker, tx| tx.close_window())
                        .build(k)
                        .key("cancel"),
                ),
        );
    col().key("picker-window").w_full().h_full().child(panel)
}
