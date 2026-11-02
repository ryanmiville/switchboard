//! Quick Switch: the shortcut and which destinations the picker shows.

use rune::{El, text};

use switchboard_core::Destination;
use switchboard_core::picker::{Favorite, PickerSettings};

use super::Ui;
use super::controls::{DESCRIPTION, Paint, note, page, scroll_body, section, setting_row, toggle_row};

pub fn pane(ui: &Ui, p: Paint, _layer: &mut Vec<El>) -> El {
    let e = &ui.editor;
    let settings = e.config.picker.clone().unwrap_or_default();
    let recorder =
        rune_kit::ShortcutRecorder::new("shortcut-recorder", &ui.recorder, |ui: &mut Ui| &mut ui.recorder)
            .on_change(|ui: &mut Ui, shortcut, _| ui.record_shortcut(shortcut))
            .build(p.k)
            .key("shortcut");
    let shortcut = setting_row(
        p,
        "shortcut-row",
        "Shortcut",
        Some("Opens the current page in another profile"),
        recorder,
    );

    let mut rows = Vec::new();
    for browser in &e.installed {
        for profile in e.profiles_of(&browser.locator) {
            let d = Destination { browser: browser.locator.clone(), profile: profile.directory.clone() };
            let shown = settings.includes(&d);
            let favorite = settings.favorites.iter().any(|f| f.destination() == d);
            let key = format!("dest-{}-{}", browser.id, profile.directory.replace(' ', "-"));
            let title = format!("{} · {}{}", browser.name, profile.name, if favorite { "  ★" } else { "" });
            let all: Vec<Destination> = e
                .installed
                .iter()
                .flat_map(|b| {
                    e.profiles_of(&b.locator)
                        .into_iter()
                        .map(|pr| Destination { browser: b.locator.clone(), profile: pr.directory })
                })
                .collect();
            rows.push(toggle_row(p, &key, &title, None, shown, move |ui: &mut Ui| {
                let d = d.clone();
                let all = all.clone();
                ui.editor.edit(|c| {
                    let mut s: PickerSettings = c.picker.clone().unwrap_or_default();
                    let mut list = s.destinations.clone().unwrap_or(all);
                    list.retain(|x| *x != d);
                    if !shown {
                        list.push(d.clone());
                    }
                    s.destinations = Some(list);
                    c.picker = Some(s);
                });
            }));
        }
    }
    if rows.is_empty() {
        rows.push(note("no-destinations", "No supported Chromium browsers were found.", p.muted()).py(12.0));
    }

    let favorites: Vec<El> = if settings.favorites.is_empty() {
        vec![
            note("no-favorites", "No favorites. Add one with switchboard-rs picker favorite.", p.muted())
                .py(12.0),
        ]
    } else {
        settings
            .favorites
            .iter()
            .enumerate()
            .map(|(i, f): (usize, &Favorite)| {
                setting_row(
                    p,
                    &format!("favorite-{i}"),
                    &f.name,
                    None,
                    text(format!(
                        "{} · {}",
                        e.browser_name(&f.browser),
                        e.profile_name(&f.browser, &f.profile)
                    ))
                    .key("destination")
                    .font(DESCRIPTION)
                    .color(p.muted()),
                )
            })
            .collect()
    };

    scroll_body(
        "quick-switch",
        page("quick-switch-page")
            .child(section(p, "shortcut", "Shortcut", vec![shortcut]))
            .child(section(p, "favorites", "Favorites", favorites))
            .child(section(p, "destinations", "Show in Quick Switch", rows)),
    )
}
