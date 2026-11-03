# Architecture of Switchboard Next

Reader: the next agent working on this branch, or the owner checking what was agreed.
Status: agreed with the owner on 2026-11-03. Being built on `swift-next`.

## Framing

A from-scratch Swift port of the Rust rewrite's design (`rune-rewrite` at `3b565e2`, paused). The
Rust code is the reference architecture and behaviour; the Swift app on `main` is a source of
SwiftUI and AppKit code to copy from. The priorities, in order:

1. The behaviours in `AGENTS.md` "Behaviour to preserve".
2. Agent convenience: JSON output, stable exit codes, files an agent can read and edit safely,
   and every app state reachable without a person.
3. Human convenience.

It runs on macOS only. Where Rust has a trait because macOS and Linux differ, Swift has a concrete
type in a module boundary instead: a protocol needs two real implementations, and a Mac-only app
has one. Everything that only reads files and starts processes stays Foundation-only, so it builds
and is tested on Linux (cloud sessions and CI) as well as on the Mac.

## Decisions

| Question | Decision |
|---|---|
| Branch | `swift-next`, started from `main` with the old sources deleted. Merges to `main` when it replaces the app |
| Rust rewrite | Paused. `rune-rewrite` at `3b565e2` is the reference; this port doesn't track later Rust changes |
| Build | SwiftPM only, no Xcode project. `scripts/bundle` assembles and signs the `.app`; `Package.swift` opens in Xcode for editing and debugging |
| Identity while both apps run | `Switchboard Next` (below). One constants file, so the final rename is one change |
| Formats | `config.json` and `history.jsonl` as the Rust rewrite writes them (`rules`, unknown keys refused). The current app's files still load |
| CLI | swift-argument-parser. The Rust CLI's commands, `--json` everywhere, its exit codes (usage errors exit 2) |
| UI | SwiftUI, macOS 13+. Panes and states as named scenes with snapshot goldens |
| Hard-coded picker favorites | Not ported. A new config has no favorites |

## Identity while both apps coexist

| | Current app (`main`) | Switchboard Next (until the merge) |
|---|---|---|
| App | `Switchboard.app`, `com.switchboard.app` | `Switchboard Next.app`, `com.switchboard.next` |
| CLI | `switchboard` | `switchboard-next` |
| Config | `~/.config/switchboard/config.json` | `~/.config/switchboard-next/config.json` |
| History | `~/.local/state/switchboard/history.jsonl` | `~/.local/state/switchboard-next/history.jsonl` |
| Test switches | | `SWITCHBOARD_NEXT_APPLICATIONS`, `_CONFIG`, `_HISTORY` |

Separate files matter: the current app's decoder drops keys it doesn't know, so its next save
would delete anything new this app writes. On first run with no config of its own, the app offers
to import the current app's config, which it reads without changing it. Every name above lives in
`Sources/SwitchboardCore/Identity.swift`.

## Modules

```
Sources/
  SwitchboardCore/      Foundation only   every rule and file format, browsers, launching
  SwitchboardCLI/       Foundation only   the commands, as a library (ArgumentParser)
  switchboard-next/     Foundation only   the CLI binary: reads the environment, calls SwitchboardCLI
  SwitchboardEditor/    Foundation only   the settings model, routing lifetime, picker model
  SwitchboardMac/       AppKit            menu bar, login item, current tab, default browser
  SwitchboardUI/        SwiftUI           panes, sheets, picker panel, scenes
  Switchboard/          SwiftUI           the app binary: @main, wiring, link delivery
Tests/
  SwitchboardCoreTests/   CLITests/   EditorTests/   UITests/ (macOS: snapshots)
```

The Rust crates map onto these:

| Rust | Swift | Notes |
|---|---|---|
| `crates/core` | `SwitchboardCore` | Same modules. `platform::Browsers` becomes a concrete `Browsers` that reads app bundles; it is file-only, so it is in core |
| `crates/platform-macos` (browsers, fixture) | `SwitchboardCore` | `Info.plist` is read with `PropertyListSerialization`, never `Bundle`, so it works on Linux |
| `crates/platform-macos` (menu bar, login item, current tab) | `SwitchboardMac` | AppKit, ServiceManagement, Apple Events |
| `crates/cli` | `SwitchboardCLI` + `switchboard-next` | The library holds the commands so the app can embed the same version; the binary is a few lines |
| `crates/app` (`editor`, `routing`, `picker` model, `watch`) | `SwitchboardEditor` | No SwiftUI, so tested on Linux |
| `crates/app` (`ui/`, `scenes`, `main`) | `SwitchboardUI`, `Switchboard` | macOS only |
| `crates/platform-linux` | none | |

Rules for the boundaries:

- **Dependencies point down only:** the app depends on UI, Mac and Editor; UI on Editor and
  Core; CLI on Core; Mac on Core. Core depends on nothing but Foundation and a vendored SHA-256.
  SwiftPM refuses imports a target doesn't declare, so the graph is checked by the compiler.
- **Foundation-only targets build on Linux.** `Package.swift` adds the AppKit and SwiftUI targets
  only on macOS. A Foundation-only file that imports AppKit fails the Linux CI job.
- **No protocols for a single implementation.** Where the app needs to choose behaviour in a test
  (a short autosave delay, a fixed clock), pass a value or a closure, never a protocol with a fake.
- **Services are structs; observable UI state is a main-actor class.** The editor's logic lives in
  a plain model the observable class wraps, so tests drive it without SwiftUI.

## Core

As `crates/core`, one file per Rust module:

- `Identity`: names, bundle ids, folder names, test variable names.
- `Home` and `Env`: every path hangs off a `Home`. `Env.fromProcess()` is the one read of the
  environment and `$HOME`; binaries call it in `main` and pass the values down.
- `Timestamp`: whole seconds since 1970, RFC 3339 text. The clock is passed in.
- `Link`: keeps the link as the exact string received. Parses only the scheme and host and never
  re-serialises; `URL` is not used for links (it re-encodes characters on recent macOS). Matching
  compares UTF-8 bytes, not `String` equality, which ignores Unicode normalisation differences.
- `Config`, `PickerSettings`: `Codable` types; unknown keys are refused; `routes` reads as
  `rules`; a rule without `browser` inherits the default; the old Carbon shortcut becomes a string.
- `ConfigStore`: revision = SHA-256 of the file's bytes; compare-and-swap saves under `flock` on
  `config.json.lock`; replace through a temporary file and `rename`; malformed files are never
  replaced.
- `Router`, `Shadowing`, `RuleOperations` (the Rust `ops`), `Profiles`, `History`, `Launch`,
  `Browsers`, `OperationError` (codes and exit codes).

## Testing

As the Rust rewrite: real implementations end to end, isolated by a temporary home. No fakes.

- **Everything takes a home folder.** Config, history, browser discovery and `Local State` are all
  found under it. A test creates a temporary home holding fixture browsers and their `Local State`
  files, then runs the real code against it. `SWITCHBOARD_NEXT_APPLICATIONS` limits discovery to
  the fixture folder.
- **Fixture browsers are real app bundles.** `Fixtures.installBrowser` writes `Name.app` with an
  `Info.plist` and a shell script as its executable that appends its arguments to a log. A test
  checks the `--profile-directory` and link a real launch passed. This runs on Linux too.
- **The CLI is tested as a binary.** Tests run the built `switchboard-next` with `--home <tmp>`
  and check its JSON, exit code and the resulting files.
- **Editor tests** drive the real model and the real store in a temporary home.
- **What can't run safely stays out of automated tests** and goes on the Mac checklist:
  registering a login item, the status item, reading a real browser tab over Apple Events,
  becoming the default browser. Their code stays thin so the logic around them is tested with
  plain values.

## Seeing the UI

- **Scenes.** Each pane and state is a named scene built on a fixture home: fixture browsers,
  profiles, rules and history. Scenes never read the real home, so renders contain no personal
  data. The list matches the Rust scenes (`general`, `routing`, `rule-edit`, `conflict`,
  `load-error`, `link-failure`, `quick-switch`, `picker`, …).
- **The app renders them headless:** `Switchboard --list-scenes`, `--snap out.png --scene routing
  --theme dark`. `scripts/snap` renders every scene in both themes.
- **Image goldens** for every scene in both themes, compared with a tolerance on macOS. CI records
  its renders as an artifact; goldens are recorded from CI's runner so CI can compare them.
- Scenes are fixtures, not end-to-end proof; reports say so.

## Order

1. Scaffold: package, `scripts/check`, lint, CI on macOS and Linux, `AGENTS.md`.
2. Core, with tests, on Linux.
3. CLI, tested as a binary, on Linux.
4. Editor model, routing lifetime and picker model, on Linux.
5. Mac glue and the SwiftUI app, scenes and goldens, `scripts/bundle` and `scripts/install`.
6. The Mac checklist with the owner. Then the merge to `main` and the rename.

## Mac checklist

Things only a person on a Mac can confirm. Record the date and macOS version when each is seen.

- [ ] `scripts/install` puts `Switchboard Next.app` in `~/Applications`, and it appears under System
      Settings → Desktop & Dock → Default web browser.
- [ ] Opening the app shows the menu-bar icon and no Dock icon or window; Settings… opens the
      window in front; Quit quits.
- [ ] With it as the default browser, a link clicked in another app opens in the right browser
      profile, with no window or icon flashing up.
- [ ] A link that can't open (a rule naming a missing profile) shows the failure with its recovery
      actions.
- [ ] Opening the app again from Finder or Spotlight brings Settings forward.
- [ ] Open at login: the toggle registers it, System Settings → Login Items lists it, and it
      starts at the next login.
- [ ] `~/.local/bin/switchboard-next` from `scripts/install --cli` runs and reads the same config.
- [ ] Quick Switch: the shortcut over a browser shows the panel without taking focus from it; the
      first time, macOS asks to allow Automation; the panel shows the current tab's link.
- [ ] Choosing a destination opens the page in that profile, brings the browser forward, and
      records a `picker` entry.
- [ ] With Automation denied, the panel says so and Automation Settings… opens the right pane.
- [ ] A change made with `switchboard-next` while Settings is open shows up within a second.
