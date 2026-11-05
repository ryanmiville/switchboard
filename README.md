# Switchboard

A personal macOS URL router that opens links in Chromium browser profiles, chosen by rules you
define, with a `switchboard` command-line tool that can do everything the app can.

A Swift port of the Rust rewrite's architecture, it replaced the previous Swift app in place: same
name, bundle identifier, settings (`~/.config/switchboard/config.json`) and history. See
[`docs/architecture.md`](docs/architecture.md) for the design and [`AGENTS.md`](AGENTS.md) for how
to work on it.

## Install

Requires macOS 14 or newer on Apple silicon.

```sh
brew install --cask ryanmiville/tap/switchboard
```

That puts `Switchboard.app` in `/Applications` and links the `switchboard` command. Every change on
`main` that passes CI is released, and the cask follows the newest release:
`brew update && brew upgrade --cask ryanmiville/tap/switchboard`. To route links through it, choose
Set Default… in Settings → General, or System Settings → Desktop & Dock → Default web browser.

From source (Xcode 26.4 or newer, Swift 6.3), `scripts/install --cli` builds the app into
`~/Applications` and links `~/.local/bin/switchboard`. Keep one copy: both have the same bundle
identifier, and macOS opens links with whichever it picks.

Upgrading from the previous Swift app: delete its copy in `/Applications` first. Settings and
history carry over as they are.

## Development

```sh
scripts/check              # Everything CI runs, on macOS or Linux
scripts/check RouterTests  # Format, lint and file sizes, then only the matching tests
scripts/format             # Apply the checked-in formatting
scripts/bundle --debug     # Build the .app into .build/bundle without installing it
scripts/snap               # Render every scene in light and dark into .build/snap
```

The core, CLI and editor model also build and test on Linux; `scripts/cloud-setup.sh` prepares a
Linux cloud session.
