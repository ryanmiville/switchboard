# Architecture of the Rust rewrite

Reader: the next agent working on the rewrite, or the owner checking what was agreed.
Status: agreed with the owner on 2026-11-02, not yet built. Supersedes the "Proposed shape" and
"Decisions for the owner" sections of `HANDOFF.md`.

## Framing

This is a from-scratch rewrite. The Swift app is a prototype that shows the required behaviour;
where it made a choice only for Swift's sake, we don't copy it. The priorities, in order:

1. The behaviours in the Swift `AGENTS.md` "Behavior to preserve" list.
2. Agent convenience: JSON output, stable exit codes, files an agent can read and edit safely.
3. Human convenience.

Runs on macOS (the owner's daily machine) and Linux. Everything that differs by platform sits
behind a trait.

## Decisions

| Question | Decision |
|---|---|
| Swift app on this branch | Replaced. The branch becomes a Cargo workspace; the Swift sources are deleted. The Swift CLI stays available in `~/reference/switchboard-swift` |
| Branch | Work lands on `rune-rewrite`. It merges to `main` once the owner is happy, and then replaces the Swift app |
| `AGENTS.md` | Rewritten from scratch for the workspace, following `agent-first-repos.md` and `rune-guide.md` |
| Name while both apps run | `switchboard-rs` (below). One constants module, so the final rename is one change |
| Look | Native-feeling kit from `Kit::from_palette`. Not final; decided from renders |
| Config and history formats | Plain `serde_json` output. No byte-for-byte match with Swift's encoder. Old Swift files still load |
| CLI | clap. Same features as the Swift CLI, `--json` everywhere, documented exit codes. Text output and help need not match Swift |
| Usage errors | Exit 2, clap's default (Swift used 64, BSD's `EX_USAGE`). Both just mean "bad command line" |
| Hard-coded picker favorites | Ported as is for now. **To remove:** the first-run favorites in `PickerSettings.initial` name the owner's own profiles |

## Identity while both apps coexist

| | Swift (installed) | Rust (until the merge) |
|---|---|---|
| App | `Switchboard.app`, `com.switchboard.app` | `Switchboard RS.app`, `com.switchboard.rs` |
| CLI | `switchboard` | `switchboard-rs` |
| Config | `~/.config/switchboard/config.json` | `~/.config/switchboard-rs/config.json` |
| History | `~/.local/state/switchboard/history.jsonl` | `~/.local/state/switchboard-rs/history.jsonl` |

Separate files matter: Swift's decoder drops keys it doesn't know and its next save would delete
anything new the Rust app writes. On first run with no config of its own, the Rust app offers to
import the Swift config, which it reads without changes. Every name above lives in
`core::identity`.

## Crates

```
crates/
  core/             switchboard-core     every rule and file format; the platform traits; fakes
  cli/              switchboard-cli      binary `switchboard-rs`; core + this platform's crate
  app/              switchboard-app      Rune UI, the editor model, scenes, goldens, the app binary
  platform-macos/   switchboard-macos    the traits, for macOS (objc2, plist)
  platform-linux/   switchboard-linux    the traits, for Linux (XDG, Rune's tray)
```

- **Traits live in core** (`core::platform`), as plain Rust with no Rune or objc2 types. The CLI
  and the app use only the traits.
- **Platform crates depend on core and nothing above it,** so there are no cycles. Each binary
  picks its implementation in one place:
  `#[cfg(target_os = "macos")] use switchboard_macos as platform;`, through target-specific
  dependencies in `Cargo.toml`.
- **Every trait has a fake** in `core::fake`, behind a `fake` feature. Tests, scenes and headless
  runs use only fakes, so they never touch real browsers, files or settings.
- Linux CI builds and tests core, the CLI, the app (headless) and `platform-linux`. macOS CI
  builds everything and tests `platform-macos`.

## Platform traits

What differs between platforms, and who implements it:

| Trait | What it answers | macOS | Linux |
|---|---|---|---|
| `Browsers` | Installed Chromium browsers: stable id, name and aliases, the executable to run, and the profile data folder holding `Local State` | Scans `/Applications` and `~/Applications`; reads `Info.plist` for the bundle id, executable and names; maps the bundle id to `~/Library/Application Support/...` | Reads `.desktop` files in the XDG application folders; maps known browsers to `~/.config/google-chrome` etc. |
| `ProcessRunner` | Starts an executable with an argument array | One `std::process::Command` implementation shared by both, in core | same |
| `LinkSource` | Links the system hands the app | Rune's `App::on_open_url` (Apple event) | The URL argument from the browser's `.desktop` `Exec=... %u` line |
| `StatusItem` | The menu-bar or tray icon and its menu, reporting choices as events | `NSStatusItem` through objc2 (Rune's tray doesn't cover macOS) | Rune's `Tray` |
| `LoginItem` | Launch at login: status, enable, disable, open the system settings | `SMAppService` | An XDG autostart `.desktop` file |
| `CurrentTab` | The URL of the focused browser's tab, for Quick Switch | Apple Events through objc2 | Returns `Unsupported`; Quick Switch shows the paste field |
| `DefaultBrowser` | Whether this app is the default browser, and how to become it | Launch Services | `xdg-settings` |

Things that are the same everywhere stay in core with no trait: reading `Local State`, routing,
rule operations, the config store, history, and the launch rule (`exe
--profile-directory=<dir> <url>`). Paths stay XDG-style (`~/.config`, `~/.local/state`) on both
platforms.

The global shortcut and the Quick Switch panel come from Rune on both platforms
(`register_shortcut`, `WindowOptions::launcher_panel()`), so they need no trait of ours.

**Known Linux gap:** a link launches a new process. Until we add forwarding to a running instance,
that process routes from the config file and exits, so it can't flush unsaved editor edits first.
The editor autosaves after half a second, which makes the gap small. Record it in the feature
map.

## Core modules

- `identity`: names, bundle ids and default paths.
- `config`: serde types and defaults; reads every Swift config shape (no `browser` on a rule,
  legacy profile display names, missing `picker`/`history`).
- `store`: revision = SHA-256 of the file's bytes; compare-and-swap saves under `flock`; atomic
  rename; malformed files are never replaced.
- `url`: keeps the URL string as received. It parses only the scheme and host, with Swift
  `URL.host` behaviour; it never re-serialises the URL (the `url` crate would change case and
  escapes).
- `router`, `shadowing`, `ops` (rule operations and the per-command profile cache).
- `profiles`: `Local State` parsing and profile-name resolution.
- `history`: storage, trimming, redaction, best-effort recording.
- `launch`: launcher over `Browsers` and `ProcessRunner`.
- `error`: error codes and their exit codes.
- `platform`: the traits above. `fake`: their fakes.

The clock, the random history ids and the home folder are passed in.

## App

- `editor`: a port of `ConfigViewModel` with no UI code: autosave delay, flush, reload, conflict
  with external changes, profile normalisation. It runs on a fake clock in plain unit tests.
- `session`: a port of `RoutingSession`, which decides when a link-only launch quits.
- `picker`: the Quick Switch model and view, in a `launcher_panel` window.
- `ui/`: a Hex-style layer of reusable pieces; General, Routing and Quick Switch panes; the rule
  editor sheet; the routing-failure window with its recovery actions ("Open Settings", "Copy
  link"), built in Rune rather than as an `NSAlert`.
- Config watching: a thread that wakes the UI when the config folder changes. The app also
  compares revisions before routing a link and when the window comes forward.
- Lifetime: `rune::App` with `.accessory().windowless().keep_running()`; `on_reopen` returns true.
- Scenes for every pane and state, element-tree goldens, and light and dark renders.

## Checking on a Mac

`spikes/mac-probe/run.sh` builds a throwaway windowless accessory Rune app that declares
`http`/`https`, sends it links with `open -a`, and reports whether they arrive (cold launch,
warm, exact string, reopen, one process, no Dock icon). It never changes the default browser.
Run it before building `LinkSource` on macOS.

**Result, 2026-11-02 (owner's Mac, macOS 26.6.2, arm64, Rune `8844e9b`):** all five probes
passed. A cold launch received the link that launched it, a running app received later links,
links arrived byte for byte (case and percent escapes kept), `on_reopen` ran, every link went to
one process, and the app ran as `UIElement` (no Dock icon). Not yet observed: delivery as the
system default browser (`run.sh --keep`), which uses the same Apple event.

The remaining Mac checklist in `HANDOFF.md` still
applies once the app exists.

## Order

As `HANDOFF.md` "Suggested order", with two changes:

- Step 1 also deletes the Swift sources, the Xcode project and the old `Makefile`.
- The macOS link probe runs before UI work, not at step 5.
