# Switchboard

A personal URL router for macOS: set as the default browser, it opens each link in a Chromium
browser profile chosen by ordered rules. A Swift port of the Rust rewrite's design (`rune-rewrite`,
paused), with a SwiftUI app and a CLI that can do everything the app can. It replaced the previous
Swift app in place, with the same names (`switchboard`, `com.switchboard.app`,
`~/.config/switchboard/`) and the same settings file; those names live only in
`Sources/SwitchboardCore/Identity.swift`.

## Layout

- `docs/architecture.md`: the agreed design and the order of work. Read it before changing
  structure.
- `Sources/SwitchboardCore`: everything that isn't drawing or AppKit: `config.json` and its
  compare-and-swap store, routing, rule edits (`RuleOperations`, `RuleChanges`), browsers from app
  bundles, Chromium profiles, history, launching. Foundation only. Reads no environment, clock or
  home folder on its own.
- `Sources/SwitchboardFixtures`: temporary homes with fixture browsers for tests and scenes.
- `Sources/SwitchboardCLI` and `Sources/switchboard-cli`: the CLI's commands (one file per
  command group in `Commands/`), the agent guide (`Guide.swift`), and the binary.
- `Sources/SwitchboardEditor`: the settings model with no SwiftUI (`Editor`: autosave, conflicts,
  import), link routing and the app's lifetime (`Routing`), the Quick Switch model (`Picker`), and
  shortcut key codes. Foundation only, so tested on Linux.
- macOS only: `Sources/SwitchboardMac` (AppKit glue: menu bar, Carbon shortcut, login item,
  current tab over Apple Events, default browser), `Sources/SwitchboardUI` (SwiftUI panes, the
  rule sheet, the picker panel, `Scenes`, `Renderer`), `Sources/Switchboard` (the app: wiring,
  link delivery, windows, `--snap`).
- `Tests/<Target>Tests`: one test target per library target.
- References, from `scripts/cloud-setup.sh` in cloud sessions: `~/reference/switchboard-rs` (the
  Rust rewrite: the behaviour and architecture to port, file for file) and
  `~/reference/switchboard-current` (the previous Swift app: SwiftUI and AppKit code to copy from).
  Elsewhere, read them with `git show 3b565e2:<path>` and `git show 43338ec:<path>`.

## Commands

- Everything CI runs: `scripts/check`. Exit codes: 10 format, 11 lint, 12 tests, 13 file sizes,
  14 build, 16 whitespace. Test failures are repeated at the end; the full log is in
  `.build/check.log`.
- A subset while iterating: `scripts/check <filter>`, such as `scripts/check RouterTests`. A
  filter that matches nothing fails. Finish with a full run.
- On Linux, `scripts/check` covers the Foundation-only targets and says what it skipped.
- Format: `scripts/format`. Swift 6.3 (Xcode 26.4 on macOS); `scripts/cloud-setup.sh` installs it
  in cloud sessions.
- Run the CLI against a scratch home: `HOME=$(mktemp -d) swift run switchboard-cli rules list`.
- See the app without a person (macOS): `scripts/snap [scene…]` renders every scene (or the
  named ones) in light and dark into `.build/snap/`; one scene:
  `swift run Switchboard --snap out.png --scene routing [--theme dark]`; list them with
  `--list-scenes`. The UI tests render every
  scene in both themes into `.build/snapshots` (CI uploads them as `scene-renders`). Scenes use
  fixture homes only. Add a scene for every new pane or state.
- Goldens: `Tests/UITests/Goldens/<scene>-<light|dark>.png`, recorded on CI's runner and compared
  there (`SNAPSHOT_COMPARE=1`); another macOS version may not match them locally. When a change
  is meant to change a scene, look at its render and `-diff` image in the failed run's
  `scene-renders` artifact, then run the **Record goldens** workflow on the branch with those
  scenes (`scenes: routing,picker`, empty for all). It records, compares again, and commits the
  goldens. Never re-record a scene you haven't looked at, or to hide a change you didn't mean.
- Build the app: `scripts/bundle [--debug]` (into `.build/bundle/`; CI's macOS job runs it).
  Install it: `scripts/install [--cli]`, only when the owner asks.
- Releases: every push to `main` that passes Verify is released by `.github/workflows/release.yml`
  (`scripts/package`: `Switchboard.zip` and `release.json`, tag `v<cliVersion>-<run>`). The cask in
  `ryanmiville/homebrew-tap` follows the newest release; the owner installs with
  `brew install --cask ryanmiville/tap/switchboard`. Bump `cliVersion` in
  `Sources/SwitchboardCLI/Arguments.swift` for a change worth a new version number.
- Check the bundled app launches and settles (no hang): `scripts/launch-check`, against a scratch
  home; CI runs it after every bundle. It is the only check that starts the app.

## How things are tested

- **Real implementations, isolated by a temporary home.** No fakes or protocols for tests. A test
  builds a `TemporaryHome` with fixture browsers (`installBrowser`): real app bundles whose
  program is a shell script that records its arguments instead of opening anything. Browser
  discovery reads `Info.plist` files, so all of this runs on Linux too.
- **The CLI is tested as a binary** (`Tests/CLITests`), checking JSON, exit codes and the
  resulting files.
- Name tests as sentences: `aSaveFromAStaleRevisionIsRefusedAndLeavesTheFileAlone`.
- For a behaviour fix, add a test that reaches the failing behaviour first.
- Cross-browser cases to keep covered: a Chrome rule with a Helium default, the same profile
  directory in two browsers meaning different people, and legacy rules with no `browser`.
- Port the Rust tests along with the code they cover, and keep their meaning.

## Behaviour to preserve

- First matching rule wins. Contains and Exact compare the whole link ignoring case; Domain matches
  the host or a subdomain at a dot. Empty patterns never match. A rule without `browser` inherits
  the default browser. Links are kept as the exact string received: never re-serialise a URL, and
  compare UTF-8 bytes, not `String`s.
- Profiles are saved as directory identifiers (`Default`, `Profile 1`) and resolved within their
  own browser. Directory identifiers beat colliding display names; ambiguous names are refused.
  Changing a rule's browser needs a new profile.
- `config.json` is shared by the app and the CLI with no daemon. Every save is a compare-and-swap
  against the loaded revision under a `flock`; never overwrite a file that changed since it was
  read. Malformed files are reported with a position, never replaced. Edits change only what they
  were asked to. Unknown keys are refused.
- Launch the browser's executable directly with an argument array, never `open -a`, so profiles
  work while the browser runs. Pass only complete http(s) links or local files.
- Surface failures with a recovery action. Never fall back to another browser or profile, or to
  the system default browser (which may be Switchboard).
- History recording is best effort: it never blocks or fails a link. CLI output redacts URLs
  unless `--full-urls`.
- The CLI never opens links and refuses ambiguous names with exit 3 instead of guessing.
- Every setting in `config.json` can be read and changed through the CLI.

## Changes

- Work lands on `main`.
- One change per commit, one line: `area: what changed`.
- Files stay under 1000 lines (`scripts/file-size`; warning at 600). Move code to a new file in its
  own commit before changing it.
- `scripts/lint.py` bans reading the home folder, the environment or the clock, starting processes,
  `NSWorkspace.open`, and `URL(string:)`/`.absoluteString` on links, outside their owners. An
  exception in `scripts/lint-exceptions.txt` needs a real reason. Warnings are errors.
- Module dependencies point down only (`docs/architecture.md`); SwiftPM enforces the declared
  graph. Foundation-only targets must stay buildable on Linux.
- No protocol with a single implementation. Pass a value or closure where a test needs control.
- A CLI or config change updates the agent guide when agents need to know.

## Autonomy

- Run the checks, fix failures, and rerun without asking.
- Commit and push to `main` once `scripts/check` passes. After pushing from Linux, watch CI's
  macOS job: it is the only check of the macOS targets.
- Ask first before: installing the app or CLI on a real machine, changing the default browser, or
  anything that touches the owner's real `~/.config` or browser data.

## Never

- Read or write the real home folder's config, history or browser data in tests or scenes.
- Open a real browser from a test.
- Weaken or skip a test to get a change through.
- Claim something works on macOS from a Linux run. Say what ran where: "checks passed on Linux;
  macOS checks not run", "CI's macOS job passed". Link delivery, the menu bar item, the shortcut,
  the picker over a real browser, Automation prompts, launch at login and the right browser window
  opening need a person on a Mac (the checklist is in `docs/architecture.md`).

## Current constraints

- 2026-11-04: this is the shipped app; it replaced the previous Swift app on `main`. The owner uses
  it daily on macOS 26 with Xcode 27.2, whose package builds record the wrong SDK (scripts/mark-sdk
  corrects it). Items in the Mac checklist in `docs/architecture.md` that the owner hasn't
  confirmed are still open.
