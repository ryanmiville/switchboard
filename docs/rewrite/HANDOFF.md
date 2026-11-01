# Handoff: rewriting Switchboard in Rust on Rune

Status, 2026-11-01: planning. No Rust code exists yet. This branch (`rune-rewrite`) holds the
plan, the reference guides and the cloud environment setup; the Swift app on `main` is
unchanged and remains the shipped version.

## Goal

Rewrite Switchboard, today a SwiftUI/AppKit menu-bar app with a Swift CLI, as a Rust app whose
UI is [Rune](https://github.com/anomalyco/rune). Keep every behaviour users rely on (the
"Behavior to preserve" section of `AGENTS.md` is the contract), keep `config.json` and the
history file readable, and set the repository up so agents can do most of the work and check
it themselves.

## What's in this branch

| File | What it is |
|---|---|
| `docs/rewrite/HANDOFF.md` | This document: the plan, what's known, what's open |
| `docs/rewrite/agent-first-repos.md` | A general guide to setting up a repository for agent development, drawn from Rune and the apps built on it. Use it when writing the new `AGENTS.md`, check script and CI |
| `docs/rewrite/rune-guide.md` | How to build apps with Rune, with patterns from three production apps (Hex, Deadbolt, Hokum). Read it before writing UI code |
| `scripts/cloud-setup.sh` | Setup script for a Claude Code cloud environment (below) |

## The starting point

The Swift app is about 6,000 lines of source and 3,500 of tests:

- **Routing core** (Foundation only, builds on Linux):
  - `Config.swift`, `ConfigStore.swift`: JSON config, compare-and-swap saves under `flock`;
  - `Router.swift`: rule matching;
  - `RuleOperations.swift`: CLI rule edits, shadowing checks;
  - `BrowserProfiles.swift`: Chromium profiles from `Local State`;
  - `History.swift`;
  - `BrowserLauncher.swift`;
  - `OperationError.swift`.
- **CLI** (`Switchboard/CLI/`, `CLI/main.swift`): `history`, `explain`, `profiles`, `route`,
  `rules`, `doctor`, `skill`, with `--json` everywhere and documented exit codes (0, 1, 3, 4,
  5, 64). Its design is `docs/cli-design.md`.
- **App** (macOS only):
  - `SwitchboardApp.swift`, `RoutingSession.swift`: URL events and lifetime;
  - `ContentView.swift`, `ConfigViewModel.swift`: the Settings window, with General, Routing
    and Quick Switch panes, the rule editor sheet and autosave;
  - `TabPicker.swift`, `PickerSettings.swift`, `CurrentTabReader.swift`: Quick Switch, which
    reads the focused browser's tab over Apple Events;
  - `GlobalShortcut.swift`, `ShortcutRecorder.swift`, `LoginItem.swift`,
    `BrowserDiscovery.swift`.
- **Tests:** 65 of them run on Linux (`make verify-linux`). The macOS-only ones cover the view
  model, picker, reopen, login item, launcher, install and snapshots. The settings window's
  golden PNGs are in `Tests/SwitchboardCoreTests/Snapshots/`, and show the look the rewrite
  starts from.

## Environment

Paste `scripts/cloud-setup.sh` into the cloud environment's settings (environment menu → Edit
→ Setup script). In about half a minute each session gets:

- Rune's Linux libraries;
- software Vulkan, so headless renders work without a GPU;
- Rust with rustfmt, clippy and cargo-nextest;
- `~/reference/rune`, a read-only checkout of Rune's docs, changelog and examples;
- `switchboard-swift`, the Swift CLI built from `8d4129a` (the last all-Swift commit), with its
  sources and tests in `~/reference/switchboard-swift`.

The base image already has Swift 6.3.3, which the script uses only to build that reference
CLI. Hex, Deadbolt and Hokum aren't cloned; clone them into `~/reference` when you want to read
their code (`github.com/anomalyco/{hex,deadbolt,hokum}`).

## Proposed shape

One Cargo workspace:

| Crate | Holds | Runs on Linux? |
|---|---|---|
| `switchboard-core` | Config and its compare-and-swap store, the router, rule operations, profile discovery from `Local State`, history, and the launcher behind an injectable process runner | Yes: all of it |
| `switchboard-cli` | The `switchboard` command: the same commands, flags, JSON and exit codes as the Swift CLI, and the agent skill | Yes |
| `switchboard-app` | The Rune UI: the Settings window and its panes, the rule editor, the Quick Switch picker, scenes, tests and goldens | Yes, headless |
| `switchboard-mac` | macOS glue behind traits with fixture implementations: the status item, the login item, reading the current tab, browser discovery and bundle executables, link events | Builds and tests on macOS only |

Where each Swift file goes:

| Swift | Rust |
|---|---|
| `Config`, `ConfigStore`, `Router`, `RuleOperations`, `BrowserProfiles`, `History`, `OperationError`, `BrowserLauncher` (its logic) | `switchboard-core` |
| `CLI/*` | `switchboard-cli` |
| `ContentView`, `ConfigViewModel`, `TabPicker`, `PickerSettings`, `ShortcutRecorder` | `switchboard-app` |
| `SwitchboardApp`, `RoutingSession` | `switchboard-app` (lifetime decisions, testable) + `switchboard-mac` (events) |
| `GlobalShortcut`, `LoginItem`, `CurrentTabReader`, `BrowserDiscovery` | `switchboard-mac`, or Rune where it covers them (below) |

## What Rune covers on macOS

I checked this by reading Rune's code and docs at `dev` `566ee5e` (30 October), not by running
anything on a Mac.

| Switchboard needs | In Rune? | Notes |
|---|---|---|
| Receiving links | `App::on_open_url` | Handles the get-URL Apple event. Documented for custom schemes; receiving `http`/`https` as the default browser is untested. Check it on a Mac first, since the whole app depends on it. The app's `Info.plist` must keep the browser declarations |
| No Dock icon | `App::accessory()` | |
| Reopen without opening Settings | `App::on_reopen` | Returning true skips Rune's default reopening |
| Global shortcut (Control–Option–Space) | `register_shortcut` / `App::global_shortcut` | Deadbolt uses it on macOS, with `rune_kit::ShortcutRecorder` for changing it |
| The picker over the focused browser | `WindowOptions::launcher_panel()` | Non-activating: takes keys while the browser stays frontmost. Deadbolt's quick panel is the model |
| Menu-bar status item | **No** | Rune's `Tray` covers Linux and Windows only. Hex creates its own `NSStatusItem` through `objc2` (`src/status_item.rs`) |
| Launch at login | **No** | Hex has its own `SMAppService` adapter (`src/login_item.rs`) |
| Reading the current tab | **No** | Apple Events through `objc2`, as `CurrentTabReader.swift` does |
| Settings window, panes, rule editor | Yes | rune-kit has the components. Hex's settings window is the closest model (`docs/rewrite/rune-guide.md`, section 3) |

## How to check the work

- **Behaviour.** Port the Swift tests to Rust as sentence-named tests. Then add a
  differential harness that runs `switchboard-swift` and the Rust CLI on the same fixture home
  (`config.json`, history, fixture `Local State` files) and compares:
  - stdout, JSON in particular;
  - exit codes;
  - the resulting `config.json`.

  Any difference is either a bug or a deliberate change, recorded with its reason.
- **Compatibility.** The Rust core reads every config shape the Swift one accepts, including
  rules without a `browser` and legacy profile display names. Keep fixtures for each.
- **UI.**
  - A scene for every pane and state: empty, errors, a missing profile, an open editor, an
    unsaved-edits conflict.
  - Element-tree goldens, and `--snap` renders in light and dark.
  - Compare the renders with the Swift goldens before deciding what to match.
- **Mac-only behaviour needs a person on a Mac:**
  - default-browser registration and link delivery;
  - the status item and the shortcut;
  - the picker over a real browser;
  - Automation prompts;
  - launch at login;
  - that the right browser window actually opened.

  Keep that checklist in the new `AGENTS.md`, and report these as not run from cloud sessions.

## Decisions for the owner

1. **Replace in place, or build beside it?** The Rust workspace could live next to the Swift
   app until it reaches parity, or replace it on this branch.
2. **Look.** Rune's OpenCode theme (what Hex and Deadbolt use), a native-feeling theme from
   `Kit::from_palette`, or a match for the current SwiftUI window.
3. **Git workflow.** `AGENTS.md` on `main` says to commit directly to `main`. This branch
   exists because the rewrite is large. Decide where rewrite work lands and when it merges.
4. **Identity.** Keep the bundle identifier, app name and CLI name, so the default-browser
   setting and installed links carry over.

## Suggested order

1. Set up the workspace with the agent-first basics:
   - an `AGENTS.md` for the rewrite;
   - `scripts/check` with one exit code per stage;
   - a strict lint configuration;
   - nextest timeouts;
   - Linux CI.
2. `switchboard-core`: config, router and store first, with the Swift tests ported and the
   differential harness.
3. `switchboard-cli` to parity with `switchboard-swift`.
4. `switchboard-app`: the Settings window and picker, with scenes and goldens.
5. `switchboard-mac`: link events first (verify on a Mac early), then the status item,
   shortcut, current tab and login item. Then the Mac checklist.

## Caveats

- The two guides were written against Rune `dev` at `566ee5e`. Rune changes quickly: check its
  `CHANGELOG.md` `## dev` section before relying on an API they name.
- Nothing in the Rune coverage table has been run on macOS.
