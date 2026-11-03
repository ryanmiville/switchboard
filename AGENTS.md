# Switchboard

A personal macOS URL router built with SwiftUI/AppKit: set as the default browser, it opens each
link in a Chromium browser profile chosen by ordered rules. A `switchboard` CLI shares its
configuration. Keep changes small and use the standard library and Apple frameworks unless a
dependency has a clear payoff. A Rust rewrite is in progress on `rune-rewrite`; this branch is the
shipped app.

## Commands

- Everything CI runs: `scripts/check`. Exit codes: 10 format, 11 lint, 12 tests, 13 file sizes,
  14 Xcode build, 15 bundle, 16 whitespace. Test failures are repeated at the end; the full log is
  in `.build/check.log`. `make verify` runs the same script.
- A subset while iterating: `scripts/check <filter>`, such as `scripts/check RouterTests` (a
  `swift test --filter` pattern). A filter that matches nothing fails. Finish with a full run.
- On Linux (cloud sessions), `scripts/check` runs formatting, lint, file sizes, the Foundation-only
  tests and whitespace, then names what it skipped. A Linux pass means "make verify not run".
  `scripts/cloud-setup.sh` is the environment's setup script; it installs the matching Swift.
- Format: `make format`. Requires Xcode 26.4 on macOS (CI: `macos-26`), Swift 6.3.x on Linux.
- Snapshots: `make snapshots` renders the settings window's scenes into `.build/snapshots` and
  compares them with `Tests/SwitchboardCoreTests/Snapshots`; `SNAPSHOT_RECORD=1 make snapshots`
  rewrites the goldens. With `CI` set they render without comparing (pixels depend on the macOS
  version); CI uploads them as the `snapshots` artifact. macOS only.
- Run the CLI against a scratch home: `HOME=$(mktemp -d) swift run switchboard rules list`.
- `make debug` / `make release` build into `.build/xcode`. `make debug-install`, `make install`
  and `make install-cli` install on the real machine: only when the owner asks.

## Where to look

| Area | Source |
| --- | --- |
| URL events, launch mode, shutdown and recovery UI | `Switchboard/SwitchboardApp.swift` |
| Routing lifetime decisions | `Switchboard/RoutingSession.swift` |
| JSON configuration and atomic persistence | `Switchboard/Config.swift` |
| Compare-and-swap saves, revisions, and file locks | `Switchboard/ConfigStore.swift` |
| Link history: storage, redaction, recording | `Switchboard/History.swift` |
| CLI rule edits: resolution, shadowing, verification | `Switchboard/RuleOperations.swift` |
| CLI commands, output, doctor, and agent skill | `Switchboard/CLI/`, entry point `CLI/main.swift` |
| Editor state, autosave and flush | `Switchboard/ConfigViewModel.swift` |
| Rule matching and preview decisions | `Switchboard/Router.swift` |
| Browser-specific profile paths and legacy names | `Switchboard/BrowserProfiles.swift` |
| Installed browsers and executable launching | `Switchboard/BrowserDiscovery.swift`, `Switchboard/BrowserLauncher.swift` |
| Editor and URL preview | `Switchboard/ContentView.swift` |
| Regression tests | `Tests/SwitchboardCoreTests/` |
| Settings window snapshots and their goldens | `Tests/SwitchboardCoreTests/SnapshotTests.swift`, `Snapshot.swift`, `Snapshots/` |
| Banned calls and their exceptions | `scripts/lint.py`, `scripts/lint-exceptions.txt` |

The Swift package leaves out the app entry point (behind `#if !SWIFT_PACKAGE`) and compiles the
editor view on macOS only, for the snapshot tests. The CLI's command definitions in
`Switchboard/CLI` compile into `SwitchboardCore` in the package; Xcode's `SwitchboardCLI` target
compiles them as one module with only the Foundation-only core files they need, and the app embeds
the result in `Contents/Helpers`. Add a core file the CLI uses to both Sources phases. New app
sources must also be added to the Xcode project's Sources phase. Files that import AppKit, SwiftUI,
Carbon, Combine, or ServiceManagement must be listed in `Package.swift`'s Linux exclusions, along
with tests that need them; keep configuration types Foundation-only so the CLI can share them.
Services are structs; observable UI state and AppKit delegates are classes with main-actor
isolation where appropriate.

## How things are tested

- Tests use temporary files and fixture browsers (`Tests/SwitchboardCoreTests/Fixtures.swift`):
  isolated configuration and Local State files, and an injected process runner instead of real
  browsers. Reopen tests call the real app delegate with isolated configuration and temporary
  AppKit windows; they don't launch the app or browsers.
- The CLI is tested in-process through `CommandContext` (`CLITests`), checking JSON, exit codes and
  the resulting files.
- One test target, `SwitchboardCoreTests`: add files to it, not new targets. Name tests as
  sentences: `malformedFileIsNotTreatedAsMissing`.
- For a behaviour fix, add a test that reaches the failing behaviour first.
- Cross-browser cases to keep covered: a Chrome rule with a Helium default, browser-specific
  profile choices, and legacy rules with no browser override.
- Snapshots show layout and drawing; they don't exercise clicks or window behaviour. Add a scene
  for every new pane or state, and record its golden on a Mac.

## Behavior to preserve

- First matching rule wins. Contains and Exact match the complete URL case-insensitively. Domain matches the host or a subdomain at a dot boundary. Empty patterns are ignored. Routing returns a browser/profile pair; unmatched URLs use the configured default browser and profile. A rule can override its browser; omitted browser fields inherit the top-level browser for compatibility with existing JSON.
- Configuration lives at `~/.config/switchboard/config.json`. Keep existing JSON readable. A missing file may use defaults; malformed or unreadable files must not be silently replaced. Saves use atomic replacement, and failures retain edits for retry.
- Persist Chromium directory identifiers (`Default`, `Profile 1`, etc.), and show display names only in the UI. Discover and validate each profile within its destination’s browser; identical directory IDs in Chrome and Helium can refer to different people. Changing a rule’s browser requires a new profile selection. Accept legacy display names only when unambiguous. Directory identifiers take precedence over colliding display names. Browser data locations are browser-specific.
- Launch the browser executable directly using `Bundle.executableURL` and a Process argument array. Do not use `open -a --args`; profiles must work when the browser is already running. Pass only complete HTTP/HTTPS URLs and preserve the original URL when launching.
- Surface failures with a recovery action. Do not guess a different browser/profile or fall back through the system default browser, which may be Switchboard itself.
- Routing must preserve an existing editor session. Flush pending edits before routing from the editor or quitting it. A temporary routing launch exits only after the latest URL's idle delay.
- Opening or reopening the app starts its menu bar and shortcut without opening Settings. Settings is a single window opened explicitly from the menu; repeated Settings requests focus or restore it, creating a window only when none is open. Suppress AppKit's default reopening.
- The CLI and the app share `config.json` with no daemon. Every save is a compare-and-swap against the loaded revision under a `flock`; never overwrite a file that changed since it was read. The CLI changes only the rules it was asked to change, refuses ambiguous names (exit 3) instead of guessing, and never opens links.
- History recording is best effort: it never blocks, delays, or fails opening a link. URLs are redacted in CLI output unless `--full-urls` is passed.
- Keep App Sandbox disabled: launching the browser requires subprocess control. Preserve HTTP/HTTPS and HTML declarations in `Info.plist` so macOS recognizes the app as a browser.

## Changes

- One change per commit, one line: `area: what changed` (such as `cli: refuse a stale revision`).
- Files stay under 1000 lines (`scripts/file-size`; warning at 600; existing exceptions in
  `scripts/file-size-exceptions.txt` may not grow). Move code to a new file in its own commit
  before changing it, and add the file to the Xcode project.
- `scripts/lint.py` bans reading the real home folder, the environment or the clock, starting
  processes, and `NSWorkspace.open` outside their owners. An exception in
  `scripts/lint-exceptions.txt` needs a real reason.
- A CLI or config change updates the agent guide in `Switchboard/CLI/Skill.swift` when agents need
  to know.
- Review changes for configuration compatibility, wrong-profile launches, swallowed failures, and
  unintended writes to personal files.

## Autonomy

- Run the checks, fix failures, and rerun without asking.
- Commit, merge, and push directly to `main` once `scripts/check` passes. Feature branches and
  pull requests aren't needed, including in cloud sessions that start on another branch (other
  than `rune-rewrite`, which stays separate).
- After pushing from Linux, watch CI's macOS `verify` job: it is the only check of the app sources,
  snapshots and Xcode builds. Fix it if it goes red.
- Ask first before: installing the app or CLI, changing the default browser, or anything that
  touches the owner's real `~/.config` or browser data.

## Never

- Read or write the real home folder's config, history or browser data in tests or snapshots.
- Open a real browser from a test.
- Weaken or skip a test, or re-record a golden you haven't looked at, to get a change through.
- Claim something works on macOS from a Linux run. Say what ran where: "checks passed on Linux;
  make verify not run", "CI's macOS job passed". A successful process launch doesn't prove the right
  browser window opened. These need a person on a Mac: link delivery from other apps, the menu bar
  item, the global shortcut, Settings opening and focusing, the picker reading a real browser's tab
  and its Automation prompt, launch at login, default-browser registration, and the right browser
  window and profile opening.

## Current constraints

- 2026-11-03: snapshots cover only the three settings panes. The error, conflict and rule-sheet
  states have none yet; add them on a Mac. Goldens aren't compared in CI.
- `scripts/check` stops tests still running after 10 minutes (`CHECK_TEST_TIMEOUT`), but Swift
  buffers test output, so it can't name the hung test; bisect with filters.
