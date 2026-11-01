# Building Apps with Rune: A Guide for Agents

Rune is a Rust GPU UI framework for desktop apps that feel like SwiftUI on iOS: views are plain
functions of state, every visual change animates on springs, and the same binary renders
headless so you can check your own work. This guide covers how Rune thinks, how to structure
an app, and the patterns three production apps use. Read it before writing or changing a
Rune UI.

**Version.** Written against `anomalyco/rune` `dev` at `566ee5e` (2026-10-30). The example
apps pin revisions from 29–30 October. Rune moves fast and has no releases: before relying on
an API here, check `crates/rune/README.md` and the `## dev` section of `CHANGELOG.md` at the
revision your app pins.

## The reference apps

Each pattern below names the file it came from. Open the file when you need the full version.

| App | What it is | What to learn from it | Start with |
|---|---|---|---|
| **Hex** (`anomalyco/hex`) | Voice dictation app; macOS menu-bar app with Windows and Linux betas | A large settings window: sidebar and panes, cards of rows, menus, modals, an onboarding tour. Its own component layer on rune-kit, a design-system doc, 114 golden PNGs, a playground, overlays with a custom shader | `docs/design-system.md`, `src/rune_ui.rs`, `src/rune_ui/controls.rs`, `src/rune_ui/general.rs`, `src/rune_ui/tests.rs` |
| **Deadbolt** (`anomalyco/deadbolt`) | Local-first password manager | Keyboard-first list and detail, screens swapped with blur replacement, a virtualized list, a written motion spec, two windows (main and a Spotlight-style panel), a worker that talks to a background agent | `docs/app.md`, `crates/app/src/lib.rs`, `crates/app/src/view.rs`, `crates/app/src/vault/mod.rs`, `crates/app/scripts/snap.sh`, `crates/app/tests/app/` |
| **Hokum** (`anomalyco/hokum`) | Notification daemon and control center for Wayland | Overlays fed from other threads, a tray panel, a settings window whose live preview reuses the overlay's view, mock backends | `src/main.rs`, `src/cards.rs`, `src/settings.rs`, `src/sound/ui/slider.rs` |

Rune's own examples are the smallest correct programs: `examples/hello` (one switch, with a
test) and `examples/todo` (keyed rows, a scrolling list, a spring).

---

## 1. The mental model

```rust
fn view(s: &State, cx: &mut Cx<State>) -> El
```

- **State is a plain struct.** The view is a function of it that returns a keyed tree of
  elements (`El`). Handlers get `&mut State`.
- **Handlers are queued** and run between frames. After they run, the view runs again. Rune
  diffs the new tree against the old one **by key** and retargets each animated property
  toward its new value.
- **Views say where things should be, and Rune animates them there.** Never step an animation
  yourself by changing state every frame. A switch's knob moves because the view put it at a
  new `x`, and the element's `.motion(spring)` says how it travels.
- **Hover and press never re-run the view.** They only retarget tracks.
- **Nothing animates on the first frame.** Elements added or removed later get entrances and
  exits (`Transition`), and stay drawn until their exit finishes.

The whole of `examples/hello`:

```rust
use rune::tok::{self, motion, type_};
use rune::{AppSpec, Cx, El, col, el, text};

#[derive(Default)]
struct State { on: bool }

fn view(s: &State, _: &mut Cx<State>) -> El {
    let t = tok::theme(true);
    let knob = el().key("knob").size(18.0, 18.0).radius(9.0).fill(t.knob)
        .absolute(if s.on { 18.0 } else { 2.0 }, 2.0);
    let switch = el().key("switch").role("switch").size(38.0, 22.0).radius(11.0)
        .fill(if s.on { tok::accent(0, true) } else { t.control_off })
        .motion(motion::SNAPPY)
        .on_press(|s: &mut State| s.on = !s.on)
        .child(knob);
    col().w_full().h_full().center().gap(16.0).fill(t.bg)
        .child(text(if s.on { "Lights on" } else { "Lights off" }).font(type_::TITLE).color(t.text))
        .child(switch)
}

fn main() {
    rune::run(AppSpec::<State> {
        scenes: &[("on", |s| s.on = true)],
        ..AppSpec::new("Hello", (320.0, 200.0), State::default, view)
    });
}
```

### Keys are identity

- **Every element that changes, moves, or is looked up gets a stable `.key(..)`.** A key is how
  Rune knows an element is the same element across frames. A list row is keyed by its item's
  id, never by its index: index keys make the wrong row leave.
- **A key path** such as `"inspector/label"` finds an element by its nearest keyed ancestors.
  `Cx::layout`, scroll requests and tests all accept them.
- **Keys share one namespace**, and rune-kit keys the parts of its components (`label`,
  `value`, `icon`, `control`, …). Prefix your own keys (`nav-general`, `item-{id}`), or rely
  on paths.
- **Sibling keys must be unique.** Debug builds print both call sites of a duplicate and rename
  the later one so the frame still draws. Treat that warning as a bug.

---

## 2. Project setup

### Dependencies

Rune isn't published to crates.io. Pin all of its crates to **one exact revision** of `dev`:

```toml
rune = { git = "https://github.com/anomalyco/rune.git", rev = "<sha>" }
rune-kit = { git = "https://github.com/anomalyco/rune.git", rev = "<sha>" }
rune-theme-opencode = { git = "https://github.com/anomalyco/rune.git", rev = "<sha>" }
```

Give every Rune crate the same `rev`. Never publish your app to crates.io with these
dependencies. See [Staying current](#12-staying-current-with-rune) for how to bump the pin.

### The spec

An app is a state type, a view and an `AppSpec`. Deadbolt's is a clean template
(`deadbolt: crates/app/src/lib.rs`):

```rust
pub fn spec() -> AppSpec<App> {
    AppSpec {
        title: "Deadbolt",
        size: (820.0, 540.0),
        min_size: Some((640.0, 420.0)),
        init: || App::new(Agent::offline()),
        view: view::app,
        scenes: SCENES,                                  // named fixture states (section 8)
        fonts: rune_theme_opencode::FONTS,               // Inter and IBM Plex Mono
        families: rune_theme_opencode::FAMILIES,
        setup: Some(setup),                              // once, with a Waker for workers
        poll: Some(|s, now, tx| s.poll(now, tx)),        // before every frame
        on_key: Some(|s: &mut App, ev: &KeyEvent, tx: &mut Tx| s.on_key(ev, tx)),
    }
}
```

If you set only some of these fields, end the literal with `..AppSpec::new(title, size, init,
view)`, as Hokum does.

### Running it

- `rune::run(spec)` opens one window and quits when it closes.
- `rune::App` gives the app its own lifetime, for menu-bar apps, tray apps and daemons:

  ```rust
  rune::App::new(spec)
      .init(move || Ui::load_with(host))   // first state from a closure
      .args(Vec::new())                    // take Rune's flags from here, not the process argv
      .keep_running()                      // closing the window keeps the process and state
      .windowless()                        // start with no window
      .accessory()                         // macOS: no Dock icon
      .on_close(|s, tx| s.flush())         // runs before every close
      .run();
  ```

- On Linux, call `rune::set_app_id("your-app")` first, so the desktop matches your window to
  its `.desktop` entry.
- If your binary has its own CLI, give Rune only the arguments meant for it: Hex passes
  `hex app -- --snap …` through with `.args(rune_args)`.

---

## 3. Structuring a settings window

Hex's window is the best model here: a sidebar of panes, each pane a scrolling column of
titled cards of rows, with menus and modals mounted above.

### One root view

From `hex: src/rune_ui.rs`, shortened:

```rust
fn view(ui: &Ui, cx: &mut Cx<Ui>) -> El {
    let p = Paint::new(cx.system_dark(), cx.env().scale);   // the kit and a hairline width
    let mut layer = Vec::new();                              // menus and popovers go here
    let body = match ui.pane {
        Pane::General => general::pane(ui, p, &mut layer),
        Pane::History => history::pane(ui, p, &mut layer),
        // one arm per pane
    };
    let panel = col().key("panel").grow(1.0).shrink()
        .radius(p.k.radius.lg).fill(p.k.c.bg_base).border(p.hair, p.k.c.border_weak)
        .child(pane_header(p, ui.pane.title()))
        .child(body);
    let window = row().key("window").fill(p.k.c.bg_deep)
        .hover_motion_within(rune::Anim::INSTANT, rune::Anim::INSTANT)
        .child(sidebar(ui, p))
        .child(panel);
    if let Some(modal) = picker::modal(ui, p) { layer.extend(modal); }
    rune_kit::root(window, layer).on_window_focus(window_focused)
}
```

- **Fetch the kit once per view**: `rune_theme_opencode::kit(cx.system_dark())`. Pass it, or a
  small `Copy` struct around it, down to every builder. Hex's `Paint` also carries a hairline
  width, `1.0 / scale`, so borders stay one device pixel.
- **Collect overlays in a `layer` vector.** rune-kit's menus, selects and popovers take
  `&mut layer` and return their trigger. `rune_kit::root(body, layer)` mounts the layer above
  everything else.
- **Give each pane a module** that owns its state struct and a `pane(ui, p, layer) -> El`
  function. The top-level `Ui` struct holds one field per pane.
- **Keep one `open: Option<Menu>` enum** for the single menu or popover that can be open.
  `on_key` closes things on Escape in priority order (explainer, sheet, picker, menu). A
  `Menu`'s `.on_close(|ui| ui.open = None)` closes it on a click outside.
- **Let what the platform can do decide what exists.** Hex's `platform::Capabilities` decides
  which panes and rows appear on each OS. A missing capability omits the row instead of
  imitating it.

### A layer of your own pieces on top of rune-kit

Hex's `src/rune_ui/controls.rs` and `src/rune_ui/lists.rs` hold every recurring piece: `page`,
`section`, `card`, `setting_row`, `toggle_row`, `segmented`, `select`, `button`,
`text_field`, `note`, `slider`. Panes compose these and nothing else. Hokum does the same at a
smaller scale (`section`, `setting`, `toggle`, `choice` in `hokum: src/settings.rs`). Its
`docs/design-system.md` lists each piece by job, which tells an agent what to reach for.

Keep layout numbers in **one struct of metrics**:

```rust
pub(super) const METRICS: Metrics = Metrics {
    gutter: 32.0,          // the page's text edge
    section_gap: 24.0,
    label_gap: 8.0,        // section label to its card
    row_px: 16.0,          // a row's inset, and how far cards hang past the gutter
    row_h: 48.0,
    row_h_described: 60.0,
};
```

A settings row is title and description on the left and a control on the right. This is
Hokum's version, which is short enough to show whole:

```rust
fn setting(k: &Kit, key: &str, title: &str, description: Option<&str>, control: El) -> El {
    let mut copy = col().key("copy").grow(1.0).shrink().gap(2.0)
        .child(text(title).key("title").font(k.ty.ui).color(k.c.text_base));
    if let Some(d) = description {
        copy = copy.child(text(d).key("description").font(k.ty.small)
            .color(k.c.text_muted).wrap().w_full());
    }
    row().key(key.to_owned()).label(title).w_full()
        .min_h(if description.is_some() { 56.0 } else { 44.0 })
        .px(12.0).py(8.0).gap(16.0).center_y()
        .child(copy)
        .child(control)
}
```

Hex adds two refinements:

- `.flex_wrap()` plus a minimum width on the copy, so a narrow window moves the control under
  the text instead of squeezing the description to a word per line.
- `.label(title)`, so the row reads as one thing to accessibility.

### Rows that toggle

The whole row presses, and the switch only shows the state (Hex):

```rust
pub fn toggle_row(p: Paint, key: &str, title: &str, description: Option<&str>,
                  on: bool, flip: impl Fn(&mut Ui) + 'static) -> El {
    let switch = Switch::new(on).build(p.k).key("switch").focusable(false);
    setting_row(p, key, title, description, switch)
        .role("toggle").focusable(true)   // the row takes focus and the press
        .on_press(flip)
}
```

### Cards of rows

A card is a raised surface with hairline separators between its rows:

```rust
fn raised(p: Paint, key: &str) -> El {
    let mut surface = col().key(key).fill(p.k.c.bg_base).radius(p.k.radius.lg);
    for shadow in &p.k.elevation.raised { surface = surface.box_shadow(*shadow); }
    surface
}
```

Use the kit's elevation layers and radii; don't invent shadows. Key each separator (`sep0`,
`sep1`, …) so it stays put when rows around it change.

### Disclosure

Keep a pane's first level short. Hokum's guide caps it at about six controls, and Hex puts the
rarely changed rows behind an **Advanced** toggle. Rows that fold away go in a slot that clips
them:

```rust
col().key("advanced-rows").clip_soft(0.0)
    .children(rows.into_iter().map(|r| r.transition(folds())))
```

Here `folds()` (`hex: src/rune_ui/controls.rs`) is a partial fade whose exit spring is
slower than the slot's close, so no sliver of a row pops.

### Scrolling bodies

A pane's body scrolls, with its edges fading only while content is hidden under them:

```rust
fn scroll_body(key: &str, content: El) -> El {
    col().key(key).grow(1.0).shrink()
        .clip_fade(0.0, 4.0, 0.0, 24.0)
        .scroll(ScrollSpec { stick_bottom: false })
        .child(col().key("inset").pt(4.0).pb(24.0).child(content))
}
```

The padding inside matches the fades, so at rest no border or ring is cut. Two layout rules
to know, both from CSS flexbox:

- A `.grow()` scroll view needs a bounded ancestor height.
- Every nested column between that ancestor and the scroll view needs `.min_h(0.0)`.

### Window chrome

On macOS, put content under a transparent title bar and place the traffic lights in your
toolbar's band. Deadbolt (`crates/app/src/view/theme.rs`):

```rust
pub const CHROME: Chrome = Chrome {
    full_size_content: true,
    traffic_lights: Some((16.0, 17.0)),
    drag_regions: true,
};
// rune::App::new(spec()).chrome(CHROME)
```

- With `drag_regions`, only elements marked `.window_drag()` move the window. Hex marks its
  sidebar and pane header.
- Clear the lights with `cx.titlebar_inset()`, which is 0 in full screen.
- **Give a settings window one fixed size** (`WindowOptions { min_size: Some(S), max_size:
  Some(S), resizable: false, .. }`). Tiling window managers then float it instead of
  stretching it. Hex and Hokum both do this.

### Copy

Hex's design system sets copy rules worth adopting:

- Sentence case everywhere.
- Row descriptions are one phrase with no closing period.
- "…" (one character) for progress and for buttons that open a further choice.
- One direct line per control: no intro paragraphs, and no state words beside switches.

---

## 4. Components, tokens and the design system

### rune-kit

rune-kit has components with the names, variants and states of OpenCode's web UI:

- **Controls:** `Button`, `IconButton`, `Switch`, `Checkbox`, `RadioGroup`, `SegmentedControl`,
  `Select`, `Menu`, `Popover`, `Tooltip`.
- **Text entry:** `TextInput`, `TextArea`, `Combobox`.
- **Feedback and structure:** `Toast`, `Card`, `Accordion`, `Badge`, `Progress`, `Spinner`,
  `Keybind`, `ShortcutRecorder`.
- **Larger views:** `Tree`, `Table`, `Markdown`, `DiffView`.
- **Desktop frame (`shell`):** `SplitView`, `Sidebar`, `Toolbar`, `Page`.

How they work:

- **Builders end in `.build(k)`.** Overlay components end in `.build(k, &mut layer)` and
  return their trigger.
- **Attach handlers through the builder** (`on_press`, `on_toggle`, `on_pick`, `on_choose`,
  `on_edit`), so a disabled component drops them.
- **Key the result** (`.build(k).key("sync")`) when you look it up or lay rows around it.
- **`shell::Page`** gives a full-window screen (settings, a lock screen) the same toolbar
  height, traffic-light clearance and framed content card as `SplitView`, so switching
  screens matches pixel for pixel. Deadbolt uses it for every screen but the vault.

A select whose choices open in a menu (Hex's `select`, shortened):

```rust
let trigger = Select::new::<&str>(format!("{key}-field"), &[])
    .appearance(SelectAppearance::Field).width(220.0)
    .current(Some(label)).open(open)
    .on_toggle(toggle)
    .trigger(p.k);
let mut menu = Menu::new(key).trigger(trigger)
    .placement(Placement::BottomEnd).gutter(4.0).min_width(220.0)
    .open(open)
    .on_close(|ui: &mut Ui| ui.open = None);
for choice in choices {
    menu = menu.item(MenuItem::new(choice.label).checked(choice.selected)
        .on_select(move |ui: &mut Ui| (choice.choose)(ui)));
}
menu.build(p.k, layer)
```

### Tokens only

- **Every colour, type style, radius, elevation and motion comes from the kit:**
  - `k.c.*`: palette, such as `text_base`, `text_muted`, `bg_base`, `border_weak`, `hover`;
  - `k.ty.*`: type;
  - `k.radius.*`;
  - `k.elevation.*`;
  - `k.motion.*`: `control`, `overlay`, `disclosure`.

  Never write a colour literal in a view. The numbers left in views are layout metrics.
- **Use one accent per screen.** The contrast button marks the one thing the person came to do.
  An ongoing state, such as recording or an available update, is a secondary button with a
  status dot, not an accent.
- **Hover belongs to one-target things:** list rows, picker rows, sidebar items. A settings row
  doesn't light up; the controls inside it do. Hex puts
  `.hover_motion_within(Anim::INSTANT, Anim::INSTANT)` on its root, so every hover below it
  switches at once, kit controls and popups included.
- **Extend a piece instead of adding a parallel helper.** Two helpers for one job drift apart.
- **Numbers that change** (counts, timers, percentages) use tabular figures,
  `TextStyle::features("'tnum' 1")`, so digits keep one width and nothing shakes.
- **For your own brand,** `Kit::from_palette(PaletteSeed { bg, fg, accent })` derives a whole
  kit from three colours. A theme crate (like `themes/opencode`) is the full version.

---

## 5. Motion: decide by who caused the change

Rune gives you springs on everything. Animating everything isn't the point: things should move
when movement explains what happened, and be instant when the person did it with their own
hand. Deadbolt's `docs/app.md` writes this down as a table with a **"who causes it"** column.
This guide's version of that table:

| Who caused the change | Example | Motion | How |
|---|---|---|---|
| The person's hand, directly | Typing filters a list, arrow keys move a selection, a pane switch, a drag | **Instant** | `tx.instant()` in the handler; `El::instant_changes()` on a subtree whose updates must land at once |
| The person, replacing a whole screen | Locked → vault, list → edit form | Whole-state replacement: blur, scale 0.96, fade | Key each screen differently and add `.transition(Transition::blur_replace())` |
| Something else: sync, another device, a worker, the OS | Rows a sync adds or removes, a status that arrives | Animate, so the person sees what changed | Rows that stay slide on `tok::motion::REFLOW`, and rows that come or go fade in place |
| State that lands just after launch | A permission state, the login-item status, a first network answer | **Instant**, so the first second stays still | `tx.instant()` when it lands |
| Time | A countdown, a one-time code's next period | Driven by the render clock, not by app wakes | A `Tween` bound with `.live_rect(..)` |

Patterns from the apps:

- **Navigation is instant.** Hokum's navigation is two lines, and Hex has a test,
  `switching_panes_is_instant`, that checks every element in the new pane has opacity 1 and
  isn't moving after one frame:

  ```rust
  fn go(s: &mut Ui, tx: &mut Tx, page: Page) { tx.instant(); s.page = page; }
  ```

- **Whole-screen replacement.** In Deadbolt's `view.rs`, each `Screen` variant builds a
  differently keyed element. The new one enters while the old one leaves:

  ```rust
  col().key("window").w_full().h_full().fill(k.c.bg_deep)
      .child(screen.grow(1.0).w_full().transition(Transition::blur_replace()))
  ```

- **Notices rise and fade:** `Transition::offset(0.0, 12.0).combined(Transition::opacity())`,
  leaving the way they came.
- **Modals scale and fade on the kit's overlay spring:**
  `Transition::scale(0.96).springs(SpringPair::new(k.motion.overlay, k.motion.overlay))`, with
  an opacity-only transition on the scrim.
- **Labels that change** roll only the changed characters. Use `rune_kit::RollingText::new(key,
  text)` or `Button::new(label).rolling(key)`; the button's width springs with the label.
- **A button that grows into its confirmation** ("Delete" becomes a dim red "Delete item?") is
  one element id in both places: `.matched(id)`.
- **Countdowns** keep a `rune::Tween` in state and bind it with `.live_rect(&tween)`. They need
  no wakes, no layout and no view re-runs.
- **Summoning a panel shows it at rest.** Call `Tx::settle()` so it appears settled instead of
  animating in.
- **Choreography** (a flash, then a cool-down, then a fade) is `El::sequence(Sequence::new(BEATS))`,
  one track with no app phases or timers.
- **Named springs.** `Spring::new(duration, bounce)` uses SwiftUI's parameters. Prefer the
  names in `tok::motion`:
  - `SNAP` 0.25 s;
  - `SETTLE` 0.3 s (the default);
  - `REFLOW` 0.4 s, for layout;
  - `GLIDE` 0.32 s;
  - `MORPH` and `POP`, which have a little bounce;
  - `DRIFT` 0.85 s.

  Each has an `_EXIT` partner that's a little faster.
- **Reduced motion is automatic.** Travel snaps, fades shorten, and loops hold still. Read
  `cx.is_reduced_motion()` only to choose a different design. In tests, call
  `rt.set_system_reduced_motion(true)`.

---

## 6. Keep the main thread free

The view, handlers, `poll` and `init` all run on the UI thread. Anything that waits blocks the
window: a socket, an HTTP request, a database query, a spawned process, a large file read.
Debug builds warn when a handler or `poll` spends 8 ms waiting.

### Workers, a waker, and a cheap poll

Every app here uses the same shape. `setup` hands a `Waker` to each worker, workers send
results over a channel and call the waker, and `poll` drains the channel. From
`deadbolt: crates/app/src/lib.rs` and `model.rs`:

```rust
fn setup(s: &mut App, waker: Waker) {
    s.agent.set_waker(waker);
    s.agent.send(Job::Connect);            // the worker thread does the socket round trip
}

pub fn poll(&mut self, now: f64, tx: &mut Tx) -> bool {
    let mut changed = false;
    for done in self.agent.drain(now) {    // non-blocking drain
        self.apply(done, tx);
        changed = true;
    }
    changed |= self.tick_copy(now, tx);
    changed                                // true only when something shown changed
}
```

- **`poll` returns true only when visible state changed.** A wake on a resting window runs
  `poll` first and draws only if it returns true, so an idle window draws nothing.
- **`poll` costs microseconds when nothing happened:** drain a channel, compare a generation
  counter. Never reload, parse or scan in it.
- **`tx.wake_after(d)` needs an end condition.** Hex's 250 ms window tick runs only while the
  window is visible.
- **For search-as-you-type, use `rune::Latest<T>`.** It runs requests on a worker, supersedes
  older ones, debounces, and wakes once per answer.

### Updating state from other threads

`app.handle()` returns an `AppHandle<S>` you can send to other threads, and `app.overlay(..)`
returns an `OverlayHandle<T>`. `handle.update(|s, tx| ..)` changes state on the UI thread and
commits on the next frame. Hokum's D-Bus thread pushes notifications straight into its overlay.
Its timer thread sleeps until the earliest deadline, then expires what's due:

```rust
pub fn timers(rx: Receiver<Option<Instant>>, handle: OverlayHandle<Ui>) {
    std::thread::spawn(move || {
        let mut next: Option<Instant> = None;
        loop {
            let msg = match next {
                Some(t) => rx.recv_timeout(t.saturating_duration_since(Instant::now())),
                None => rx.recv().map_err(|_| RecvTimeoutError::Disconnected),
            };
            match msg {
                Ok(t) => next = t,
                Err(RecvTimeoutError::Timeout) => {
                    next = None;
                    handle.update(|s, _| s.expire(Instant::now()));
                }
                Err(RecvTimeoutError::Disconnected) => break,
            }
        }
    });
}
```

Use `handle.update_if(|s, tx| { ..; false })` for work that changes nothing on screen (storing
a handle, starting a status item). Returning false asks for no frame.

### Launch fast

- Call `rune::prewarm_gpu()` first in `main`, when the process will open a window. On macOS it
  builds the GPU device while AppKit starts.
- Keep `init` and the first `view` cheap: build the first frame from memory or a small file.
- Start everything else from `on_ready`, which runs after the first frame. Hex starts its
  status item, HUD and menus there:

  ```rust
  app = app.on_ready(move |_| { ready.update_if(|_, _| { start_main_thread(); false }); });
  ```

### Save text fields after a pause

Hex saves a text field's edits 250 ms after typing stops, not on every key. It also saves at
once when the window closes or the person leaves the pane (`save_drafts` and `flush_drafts` in
`hex: src/rune_ui.rs`).

### Lists, layout reads and live values

- **Long lists use `virtual_rows`,** which builds only the rows in view. Wrap each row in
  `rune::memo` with a small version. From `deadbolt: crates/app/src/vault/mod.rs`:

  ```rust
  rows.virtual_rows(
      keys.len(),
      ROW_H,
      move |s: &App, i| format!("item-{}", s.items[keys[i]].id).into(),   // stable key
      move |s: &App, i| {
          let item = &s.items[items[i]];
          let on = s.selected.as_deref() == Some(item.id.as_str());
          rune::memo(format!("item-{}", item.id),
                     (&item.label, &item.detail, &item.kind, on),          // small version
                     || list_row(&k, item, i, on))
      },
  )
  .virtual_rows_version(version)   // a hash of the visible ids, so keys rebuild only on change
  ```

  `.virtualize(h)` takes rows you've already built. Use it only for short lists or empty
  states. Never use a large value (a whole document) as a memo version: hashing it costs what
  the memo saves.
- **Read sizes, not rects.** `cx.layout_size(key)` re-runs the view only when the size changes.
  `cx.layout(key)` re-runs it whenever the rect moves, which is every frame inside a scroll
  view.
- **Measure with `on_layout`.** Hokum records each card's height with
  `.on_layout(|s, r: [f32; 4]| s.measured(id, r[3]))`, then decides how many cards fit.
- **High-frequency values bypass the view.** `Live<T>` (`f32`, `[f32; 2]`, `[f32; 4]`, `Color`)
  binds straight to a property: `.live_opacity(&level)`, `.live_offset(&p)`,
  `.live_scale(&s)`, `.live_rect(&r)`. Any thread can `set` it, and no view or layout runs. A
  handler that only moves live values calls `tx.live_only()`. Hex's capture capsule animates
  its rings and glyphs this way.
- **Bound every cache** in entries and in bytes, counting decoded pixels. `rune::ImageCache`,
  made with the waker in `setup`, decodes images off the UI thread.

---

## 7. Seams: fixtures, mocks and safe headless runs

Every external system the UI talks to sits behind a seam with a fixture side. Tests and
snapshots never touch the real thing.

- **A service enum with a recording fixture.** Hex (`src/rune_ui.rs`):

  ```rust
  enum Service {
      Pending(host::Connect),     // setup connects
      Live(Box<Backend>),
      Fixture(Vec<Request>),      // snapshots and tests: requests are recorded, never sent
  }
  ```

  Tests then check behaviour by what was asked for, not by what happened to a real system:
  `assert!(sent(&rt).is_empty(), "switching panes saves nothing")`.
- **Mock backends behind a contract.** In Hokum, each module has a `model.rs` (the contract), a
  real backend and `mock.rs`, chosen by `HOKUM_SOUND_BACKEND=mock`. Its guide forbids running
  against the developer's real devices.
- **Headless runs never get real data.** Deadbolt gives tooling runs (`--snap`, `--tree`,
  `--script`) no agent connection, so a snapshot or tree dump can never contain a real vault.
  Rune keeps headless runs off the system clipboard. Detect them with
  `rune::tooling::Args::parse().headless()` or `rune::is_headless()`.
- **Fixtures can simulate latency.** Deadbolt's 243-row scene has a fake agent that answers on
  the app's clock with a fixed cost per request, so tests can check the UI under a realistic
  backlog.

---

## 8. Seeing your work: scenes and headless renders

You can't look at a window, but the app can render itself. Use this loop for every UI change.

### Scenes

A scene is a named starting state, registered in `AppSpec::scenes`:

```rust
type Scene = (&'static str, fn(&mut Ui));
const SCENES: &[Scene] = &[
    ("portal", |ui| *ui = portal_fixture()),
    ("disabled", |ui| {
        *ui = portal_fixture();
        if let Some(view) = &mut ui.view {
            view.listener.running = false;
            view.listener.status = "Disabled".into();
        }
    }),
    // one per pane and per state worth seeing: empty, loading, error, long text, other languages
];
```

- Cover every pane and every state, including errors and edge cases. Hex has scenes for "microphone
  missing", "lid closed", "Chinese UI" and each step of the onboarding tour.
- List the important scenes in your `AGENTS.md`, so the next agent knows what to render.
- A scene is a fixture, not end-to-end proof. Say so when you report a check.

### Headless flags

Every Rune app binary accepts these:

```sh
app --list-scenes
app --snap out.png --scene settings --theme light --size 980x760 --scale 2
app --snap mid.png --scene creating --at 1.34          # a frame mid-animation
app --tree tree.json --scene settings                  # keys, roles, text, rects, opacity, colours
app --script tap.json --frames 30 --out frames/        # scripted input by element key
app --script demo.json --video demo.mp4
app --window panel --scene locked --snap panel.png     # one window of a multi-window app
```

- **Scripts target elements by key:** `{"events": [{"t": 0.1, "type": "tap", "key": "sounds"}]}`.
- **On a machine without a GPU,** render on Mesa's software Vulkan:
  `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json`.
- **Render both themes of every scene you touched, and look at the images.**

### A visual inventory script

Deadbolt's `crates/app/scripts/snap.sh` renders 166 stills: every scene in dark and light,
plus timed frames mid-animation (`--scene creating --at 1.34`). Run it before and after a change
or a Rune bump, and compare the two folders.

### Rendering overlays headlessly

Overlays have no window to snapshot. Hokum wraps its card overlay's view in an `App` of its own
over a gradient "desktop", with scenes for each theme (`cards::headless` in
`hokum: src/cards.rs`). `hokum service --snap cards.png --scene demo` then renders the cards
as they'd look on screen.

### The playground

`App::playground` is a storybook inside the running app. ⌘⇧D opens it in debug builds. Hex lists
every fixture scene in it under a readable path (`"Window/General/Advanced"`). A test checks
that every scene has a path, so new scenes can't be forgotten. Tests can open a story
headlessly with `App::headless_runtime` and `open_playground`.

### Read Rune's warnings

Debug builds print warnings to stderr, once per call site, when Rune sees a mistake:

- a handler or `poll` blocked on the main thread;
- `poll` returning true for 30 frames while nothing on screen changed;
- a `.virtualize` list handed hundreds of built rows;
- a scroll view that collapsed to 0 pt;
- duplicate sibling keys;
- a `live_only` handler that changed what the view reads.

Read stderr after a run, and treat each warning as a bug. `scripts/app-audit <repo>` in Rune
greps an app for the same slow patterns.

---

## 9. Testing

A test builds a `Runtime` from a state and a view, steps it frame by frame, and reads back what
it laid out. No window, no GPU.

```rust
use rune::{Env, Runtime};

fn runtime(scene: &str) -> Runtime<App> {
    let app = rune::tooling::initial_state(&spec(), Some(scene));   // start from a scene
    let mut rt = Runtime::new(app, view::app, (820.0, 540.0),
                              Env { system_dark: true, scale: 1.0 });
    rt.poll = Some(|s, now, tx| s.poll(now, tx));
    rt.on_key = Some(|s, ev, tx| s.on_key(ev, tx));
    for _ in 0..60 { rt.frame(1.0 / 60.0); }                         // settle
    rt
}

fn tap(rt: &mut Runtime<App>, key: &str) {
    let (x, y) = rt.find(key).unwrap_or_else(|| panic!("no element {key}"));
    rt.pointer_down(x, y);
    rt.pointer_up(x, y);
    for _ in 0..60 { rt.frame(1.0 / 60.0); }
}
```

These calls do most of the work:

- `rt.frame(dt)` steps the clock.
- `rt.find(key)` returns an element's centre.
- `rt.key(KeyEvent { key, mods })` and `rt.wheel(x, y, dy)` send input.
- `rt.update(|s, tx| ..)` changes state as a handler would.
- `rt.elements()` returns every element's `key`, `path`, `rect`, `opacity`, `text`, and whether
  it is `moving` or `exiting`.
- `rt.presented(key)` returns one element's presented rect and opacity.
- `rt.settle_all()` lands everything.

### What to test

Name tests as sentences, so a failure reads as the broken promise.

- **Behaviour, through the seam.** Press a control, then check the state and the recorded
  requests (`the_sidebar_switches_panes_and_keeps_settings`).
- **Instant where the hand acts.** One frame after the press, every element in the new view has
  opacity 1, isn't `moving`, and nothing is `exiting` (Hex `switching_panes_is_instant`, Hokum
  `screens_switch_without_fading`).
- **Moves, not jumps.** Sample mid-flight and check the value lies between start and end:

  ```rust
  assert!(from < y && y < to, "the button moves, not jumps ({from} -> {y} -> {to})");
  ```

  (Deadbolt `an_unlock_error_fades_in_and_the_button_moves_down`.)
- **Idle means idle.** Hex's `every_scene_stops_asking_for_frames` runs every scene for 5 s and
  checks that nothing is still moving except a known loop. It then turns on reduced motion and
  checks that no scene asks for another frame.
- **Stress the hand.** Deadbolt's `holding_down_shows_a_whole_page_every_frame` holds the down
  arrow through 243 rows at key-repeat speed. On every frame it checks that the highlight is on
  the selected row and that the backlog of agent requests stays small.
- **Completeness.** Every scene has a playground path, every translated string exists in every
  language, and every keyboard shortcut in the help sheet matches the key map (Deadbolt's
  `keymap.rs`).

### Golden images

Hex keeps 114 golden PNGs (`tests/golden/`), each scene rendered in light and dark at scale 2.
From `hex: src/rune_ui/tests.rs`:

- **One GPU device for every golden,** behind a mutex: creating devices from parallel test
  threads crashed a Linux driver. Without a GPU adapter, the test skips.
- **Compare with a tolerance.** A pixel counts as different past 12 levels in any channel, and
  the test fails past 1 in 500 pixels. Drivers differ in the last bit of blending; a layout or
  colour change moves far more than that.
- **On a miss, write the actual render** to a temp file and print its path.
  `HEX_UPDATE_GOLDENS=1` rewrites the goldens.
- **Run image goldens on one platform** (Hex uses Linux) and have CI upload the actual renders
  as an artifact when they fail.
- **Look at every changed image** before committing it with the change that caused it.

Rune also ships `rune::motion_gate`, which records every element per frame in your own test and
fails on pops, jumps, overshoot and motion that never settles, with an allowlist that requires
reasons. None of these apps use it yet, but it's the strongest motion check available.

---

## 10. Windows, overlays, panels and the menu bar

### A menu-bar app (Hex on macOS)

One `rune::App`, `.accessory()` (no Dock icon), and `.windowless()` or `.keep_running()`
depending on whether the window opens at launch. The status item, menus and HUD start from
`on_ready` on the same main loop. Closing the window hides it, and Quit drains the worker
threads before exiting. See `hex: src/macos_rune.rs`.

### Two windows with different state (Deadbolt)

`rune::run_windows_with(RunOptions { accessory }, |_| vec![..])` runs a main window and a quick
panel on one event loop, each with its own `App`, state and agent connection.
`WindowOptions::launcher_panel()` makes the panel borderless, transparent and non-activating: it
takes keys while the app you were in stays frontmost. A global shortcut toggles it
(`AppHandle::register_shortcut`), and `rune_kit::ShortcutRecorder` lets the person change the
shortcut. Hidden windows keep their state, so a summon costs a show, not a launch.

### Overlays (Hokum, Hex)

```rust
let overlay = app.overlay(
    OverlaySpec::new("hokum", size, view)
        .options(OverlayOptions {
            placement: Some(placement),
            input: OverlayInput::Regions,      // only elements marked `.hit()` take the pointer
            ..OverlayOptions::default()
        })
        .setup(|ui, waker| ui.cache = Some(rune::ImageCache::new(waker)))
        .animate_reveal(),                     // motion started while hidden plays on show
    cards::Ui::new(config, out_tx, timer_tx),
);
overlay.update(|c, _| c.upsert(note));         // from any thread
```

- An overlay is transparent, above every app, never focused, and never activates the app.
- Clicks pass through it unless it is `interactive`, or, with `OverlayInput::Regions`, except
  over elements marked `.hit()` (Hokum's cards and its "Clear all" pill).
- It works on Wayland (layer shell), X11, macOS (a non-activating panel) and Windows.
- **Share views between surfaces.** Hokum's `cards::stack` draws both the overlay and the live
  preview inside its settings window, so the preview can't drift from what ships.
- **Custom GPU drawing** goes through a `Compositor`. Hex's HUD draws its scope with a WGSL
  shader that way: `.compositor(HudCompositor { .. })`. Return `animating() == true` only while
  it moves, so the overlay can rest.

### Links and focus

- **`App::on_open_url`** receives `myapp://` links on macOS. Hex opens playground stories from
  `hex://story/…` links. Parse and validate every link: anyone who can run `open` can send one.
- **`.on_window_focus(|s, focused, tx| ..)`** on the root hears the window coming forward. Hex
  re-reads Screen Recording permission then, because people often grant it in System Settings
  and come back.

---

## 11. Keyboard and accessibility

- **Custom controls need a `role` and a `label`.** Hokum's volume slider sets
  `.role("slider").label(..)` and handles everything a slider should:
  - `.on_drag(..)` for the pointer;
  - `.on_wheel(..)`;
  - `.on_step(|s, n, tx| ..)` for arrows and Page Up and Down;
  - `.on_step_limit(|s, max, tx| ..)` for Home and End;
  - `.on_key(..)` for M to mute.

  Hex's custom select trigger sets `.role("combobox")` and a label with its value.
- **Focus:**
  - `.focusable(true)`;
  - `.focus_ring(width, offset, k.c.border_focus)` draws a ring for keyboard focus only;
  - `.focus_group()` gives arrow-key roving and type-select in lists and menus;
  - `.modal(click_outside, close)` traps Tab, handles Escape and restores the opener;
  - `.default_button()` marks the button Return presses.
- **Keep one key map** that the help sheet, Settings and the handlers all read, and test it.
  Deadbolt's `keys::SHORTCUTS` is checked by `tests/app/keymap.rs`.
- **Routing:** the window's `on_key` sees keys nothing focused took. Return goes to the default
  button unless a focused field or row takes it, and Escape closes the innermost open thing.
- **Gaps at these revisions:**
  - Rune has no OS accessibility bridge yet. Roles and labels reach the element tree, `--tree`
    and tests, but not screen readers.
  - A focus change made from state lands on the next frame, so tests need a frame between
    Enter and typing.

---

## 12. Staying current with Rune

Deadbolt and Hex both follow this at the start of each round of work:

1. Bump every Rune `rev` to the head of `dev`, then run `cargo update -p rune -p rune-kit -p
   rune-theme-opencode`.
2. Read the `## dev` entries of Rune's `CHANGELOG.md` since the old pin. Entries marked
   **Breaking:** give the exact migration steps.
3. Run the tests and the visual inventory script, and compare stills before and after.
4. If Rune itself is broken, report it to Rune with a minimal case. Don't work around it in the
   app.

Keep a **"Rune gaps"** section in your app's docs, as Deadbolt does (`docs/app.md`):

- what each bump changed in your pixels;
- what you adopted;
- what you still need from Rune.

When Rune ships something you worked around, delete the workaround. Deadbolt's "Stand-ins"
section records the ones it retired.

Rune's `dev` branch is fast-forward only, so a pinned revision always stays fetchable.

---

## 13. Before you call a UI change done

- [ ] Rendered every scene you touched, in light and dark, and looked at the images.
- [ ] Goldens regenerated, each changed image looked at, and committed with the change.
- [ ] Changes made by the hand are instant, other changes move rather than jump, and an idle
      window stops asking for frames.
- [ ] Nothing in `view`, handlers, `poll` or `init` blocks; `poll` returns true only on a change.
- [ ] Every colour, type style and radius comes from the kit; you reused an existing piece where
      one fits.
- [ ] New elements have stable, scoped keys; lists are keyed by id.
- [ ] Custom controls have a role, a label and keyboard handling.
- [ ] Reduced motion checked.
- [ ] No Rune warnings on stderr.
- [ ] New states have scenes, and `AGENTS.md` lists them.

---

## Appendix: gotchas

- **`.grow(g)` is `flex: g 1 0`.** A grown scroll view in an auto-height column collapses to 0 pt.
  Bound an ancestor's height (`.h(..)`, `.h_full()`) or set `.min_h(..)`.
- **Nested flex columns don't shrink** below their content. Put `.min_h(0.0)` on each column
  between the bounded ancestor and the scroll view.
- **`.virtualize(..)` works only on a growth stack** (`.growth(GrowthSpec { .. })` on the same
  element) that is the scroll view's first child.
- **Don't set `TextEdit::focused` on every rebuild.** Set it once to request focus; the runtime
  clears it when another field takes focus. Use `Tx::blur()` to drop focus.
- **Assigning `TextEdit::text` directly** bypasses secure wiping. Use `replace_text(..)` or
  `clear()`.
- **`cx.reduced_motion(value)` overrides for one commit only.** Call it on every view run if you
  need it, as Deadbolt does for its `--reduced-motion` flag.
- **`tx.live_only()` in a handler that changed what the view reads** leaves the screen stale
  until something else commits. Debug builds check for this.
- **Copy secrets with `tx.copy_secret(text, Duration::from_secs(30))`.** It marks the copy as
  excluded from clipboard history and clears it on expiry.
- **Headless runs drop window requests** (show, focus, activate), so tests can't see a window
  come forward.
