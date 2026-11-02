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
  core/             switchboard-core     every rule and file format; the platform traits
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
- **No fakes.** Tests use the real implementation for the platform they run on (Linux in CI,
  macOS on the owner's Mac). Isolation comes from a temporary home, not from substitutes: see
  [Testing](#testing).
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
- `platform`: the traits above.

The clock, the random history ids and the home folder are passed in.

## App

- `editor`: a port of `ConfigViewModel` with no UI code: autosave delay, flush, reload, conflict
  with external changes, profile normalisation. Its autosave delay is a parameter, so tests can use a short one.
- `session`: a port of `RoutingSession`, which decides when a link-only launch quits.
- `picker`: the Quick Switch model and view, in a `launcher_panel` window.
- `ui/`: a Hex-style layer of reusable pieces; General, Routing and Quick Switch panes; the rule
  editor sheet; the routing-failure window with its recovery actions ("Open Settings", "Copy
  link"), built in Rune rather than as an `NSAlert`.
- Config watching: a thread that wakes the UI when the config folder changes. The app also
  compares revisions before routing a link and when the window comes forward.
- Lifetime: `rune::App` with `.accessory().windowless().keep_running()`; `on_reopen` returns true.
- Scenes for every pane and state, element-tree goldens, and light and dark renders (see
  [Seeing the UI](#seeing-the-ui)).

## Testing

Decided 2026-11-02 after reading how Deadbolt, Hex and Hokum test (below): real implementations
end to end, isolated by a temporary home.

- **Everything takes a home folder.** Config, history, browser discovery and `Local State` are all
  found under it. A test creates a temporary home holding fixture browsers (`.app` folders with
  an `Info.plist` on macOS, `.desktop` files on Linux) and their `Local State` files, then runs
  the real code against it.
- **The CLI is tested as a binary.** Tests run the built `switchboard-rs` with `--home <tmp>` (or
  `--config`/`--history-file`) and check its JSON, exit code and the resulting files.
- **Launching is tested with a real process.** Each fixture browser's executable is a tiny
  program that writes its arguments to a file in the temporary home. A test then checks the
  `--profile-directory` and URL a real launch passed. No real browser opens, and nothing is
  substituted.
- **App tests** drive Rune's headless `Runtime` on the real editor and the real store in a
  temporary home, as Deadbolt's app tests drive its real daemon.
- **What can't run safely stays out of automated tests,** and goes on the Mac checklist instead:
  registering a login item, the status item, reading a real browser tab over Apple Events,
  becoming the default browser. Their code is kept thin so the logic around them (what to show
  for each login-item status, how to parse a tab's reply) is tested with plain values.
- **Test-only switches, if ever needed,** are read only in debug builds (Deadbolt's
  `DEADBOLT_KDF=fast` pattern) and listed in `AGENTS.md`.
- **A new trait needs two real implementations** (macOS and Linux), never a test double alone.
  This is Hex's rule: add a seam once there are two real adapters or a current test needs
  substitution.

What the reference apps do:

| App | Approach |
|---|---|
| Deadbolt | End to end. CLI tests start real daemon processes in temporary homes and sync them over localhost. App tests drive the headless Rune runtime against a real daemon. Debug-only switches make key derivation fast and keep networking local |
| Hex | A `Service::Fixture` that records requests, for UI tests and scenes, so they never write the user's settings |
| Hokum | Mock PipeWire and Bluetooth backends (about 2,000 lines), chosen by an environment variable, because the real ones would change the developer's actual audio devices |

Switchboard is closest to Deadbolt: its platform work is reading files and starting processes,
which a temporary home makes safe. That is why we don't need Hokum's mocks.

## Seeing the UI

Agents must be able to see every screen without a display, as in Hex and Deadbolt:

- **Scenes.** Each pane and state is a named scene built on a fixture home checked into the repo
  (`crates/app/fixtures/home`): fixture browsers, profiles, rules and history. Headless runs use
  only that home and never read the real one, so renders are the same on every machine and can't
  contain personal data.
- **Headless flags** (Rune's): `--list-scenes`, `--snap out.png --scene <name> --theme dark`,
  `--tree out.json`, `--script`. On a machine with no GPU, Mesa's software Vulkan renders them.
- **Element-tree goldens** (keys, roles, text, rects) for every scene, checked on every platform.
- **Image goldens** for every scene in light and dark, at scale 2, compared with a tolerance.
  Like Hex, they run on Linux only, since pixels differ by GPU and OS. CI uploads the actual
  renders when one fails, so a Mac session can download and look at them.
  `UPDATE_GOLDENS=1 scripts/check` rewrites them; look at every changed image before committing.
- **`scripts/snap`** renders every scene in both themes into a folder, to compare before and
  after a change or a Rune bump.
- Scenes are fixtures, not end-to-end proof; reports say so.

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

## Mac checklist

Things only a person on a Mac can confirm. Record the date and macOS version when each is seen.

- [ ] `scripts/install` puts `Switchboard RS.app` in `~/Applications`, and it appears under System
      Settings → Desktop & Dock → Default web browser.
- [ ] Opening the app shows the menu-bar icon and no Dock icon or window; Settings… opens the
      window in front; Quit quits.
- [ ] With it as the default browser, a link clicked in another app opens in the right browser
      profile, with no window or icon flashing up.
- [ ] A link that can't open (a rule naming a missing profile) shows Settings with the notice.
- [ ] Opening the app again from Finder or Spotlight brings Settings forward.
- [ ] Open at login: the toggle registers it, System Settings → Login Items lists it, and it
      starts at the next login.
- [ ] `~/.local/bin/switchboard-rs` from `scripts/install --cli` runs and reads the same config.
- [ ] Quick Switch: ⌃⌥Space over a browser shows the panel without taking focus from it; the first
      time, macOS asks to allow Automation for that browser; the panel shows the current tab's link.
- [ ] Choosing a destination (click, Return, or ⌘1–⌘9) opens the page in that profile, brings the
      browser forward, and records a `picker` entry (`switchboard-rs history`).
- [ ] With Automation denied, the panel says so and Automation Settings… opens the right pane.
- [ ] Recording a new shortcut in Settings → Quick Switch works at once, and a taken chord is refused.
- [ ] A change made with `switchboard-rs` while Settings is open shows up within a second.
