# Switchboard

A personal URL router: set as the default browser, it opens each link in a Chromium browser profile
chosen by ordered rules. A Rust rewrite of the Swift app on `main`, with a Rune UI, a CLI that can
do everything the app can, and macOS and Linux support. Until it replaces the Swift app it is called
**Switchboard RS** (`switchboard-rs`, `com.switchboard.rs`, `~/.config/switchboard-rs/`); those names
live only in `crates/core/src/identity.rs`.

## Layout

- `crates/core`: everything that isn't drawing or OS glue: `config.json` and its compare-and-swap
  store, routing, rule edits (`ops.rs`), Chromium profiles, history, launching, and the platform
  traits (`platform.rs`). Reads no environment, clock or home folder on its own.
- `crates/cli`: the `switchboard-rs` binary. `src/cli.rs` is the command line, `src/commands/` one
  file per command, `src/guide.md` the agent guide `skill show` prints.
- `crates/app`: the Rune app: settings window, Quick Switch picker, scenes and goldens.
- `crates/platform-macos`, `crates/platform-linux`: the platform traits for each OS, plus
  `fixture.rs`, which installs fixture browsers for tests and scenes. File-only code compiles and
  is tested on both platforms; AppKit glue is `cfg(target_os = "macos")`.
- `docs/rewrite/architecture.md`: the agreed design. Read it before changing structure.
- `docs/rewrite/rune-guide.md`: how to build Rune UIs. Read it before UI work.
- `docs/rewrite/swift-cli-design.md`: the Swift CLI's design, the source of the CLI's behaviour.
- `spikes/mac-probe`: a throwaway probe of macOS link delivery (results in `architecture.md`).

## Commands

- Everything CI runs: `scripts/check` (exit codes: 10 format, 11 clippy, 12 tests, 13 file sizes).
- A subset: `scripts/check <filter>`, such as `scripts/check route`. Read the output whole;
  failures are summarised at the end.
- Format: `cargo fmt --all`.
- Run the CLI against a scratch home: `HOME=$(mktemp -d) cargo run -q -p switchboard-cli -- rules list`.
- Rust is pinned in `rust-toolchain.toml`; rustup installs it on first use.

## How things are tested

- **Real implementations, isolated by a temporary home.** No mocks or fakes. A test builds a home
  with fixture browsers (`platform::fixture::install_browser`): real app bundles on macOS, real
  desktop entries on Linux, whose program records its arguments to a file instead of opening
  anything. `$SWITCHBOARD_RS_APPLICATIONS` limits browser discovery to the fixture folder.
- **The CLI is tested as a binary** (`crates/cli/tests/cli/`, one module per command), checking
  JSON, exit codes and the resulting files.
- Each crate has at most one integration-test binary; add modules to it, not new files in `tests/`.
- Name tests as sentences: `a_stale_revision_exits_5_and_leaves_the_file_alone`.
- For a behaviour fix, add a test that reaches the failing behaviour first.
- Cross-browser cases to keep covered: a Chrome rule with a Helium default, the same profile
  directory in two browsers meaning different people, and legacy rules with no `browser`.

## Behaviour to preserve

- First matching rule wins. Contains and Exact compare the whole link ignoring case; Domain matches
  the host or a subdomain at a dot. Empty patterns never match. A rule without `browser` inherits
  the default browser. Links are kept as the exact string received: never re-serialise a URL.
- Profiles are saved as directory identifiers (`Default`, `Profile 1`) and resolved within their
  own browser. Directory identifiers beat colliding display names; ambiguous names are refused.
  Changing a rule's browser needs a new profile.
- `config.json` is shared by the app and the CLI with no daemon. Every save is a compare-and-swap
  against the loaded revision under a `flock`; never overwrite a file that changed since it was
  read. Malformed files are reported, never replaced. Edits change only what they were asked to.
- Launch the browser's executable directly with an argument array, never `open -a`, so profiles
  work while the browser runs. Pass only complete http(s) links or local files.
- Surface failures with a recovery action. Never fall back to another browser or profile, or to
  the system default browser (which may be Switchboard).
- History recording is best effort: it never blocks or fails a link. CLI output redacts URLs
  unless `--full-urls`.
- The CLI never opens links and refuses ambiguous names with exit 3 instead of guessing.
- Every setting in `config.json` can be read and changed through the CLI.

## Changes

- Work lands on `rune-rewrite`, not `main`, until the owner merges the rewrite.
- One change per commit, one line: `area: what changed`.
- Files stay under 1000 lines (`scripts/file-size`; warning at 600). Move code to a new module in
  its own commit before changing it.
- Lint rules are errors. `clippy.toml` bans reading the environment, the clock and starting
  processes outside their owning modules; an `#[expect(..., reason = "...")]` needs a real reason.
- Add a seam (trait) only when there are two real implementations (macOS and Linux), never for a
  test alone.
- A CLI or config change updates `crates/cli/src/guide.md` when agents need to know.

## Autonomy

- Run the checks, fix failures, and rerun without asking.
- Commit and push to `rune-rewrite` once `scripts/check` passes.
- Ask first before: installing the app or CLI on a real machine, changing the default browser, or
  anything that touches the owner's real `~/.config` or browser data.

## Never

- Read or write the real home folder's config, history or browser data in tests or scenes.
- Open a real browser from a test.
- Weaken or skip a test to get a change through.
- Claim something works on macOS from a Linux run. Say what ran where: "check passed on Linux",
  "not run on macOS". Link delivery, the status item, the shortcut, the picker over a real browser,
  Automation prompts, launch at login and the right browser window opening need a person on a Mac.

## Current constraints

- 2026-11-02: the rewrite is in progress. Order: core and CLI (done), then the Rune app, then the
  macOS glue. See `docs/rewrite/architecture.md`.
