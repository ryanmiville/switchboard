# Switchboard

A personal macOS URL router that opens links in Chromium browser profiles, chosen by rules you
define, with a `switchboard` command-line tool that can do everything the app can.

A Swift port of the Rust rewrite's architecture, it replaced the previous Swift app in place: same
name, bundle identifier, settings (`~/.config/switchboard/config.json`) and history. See
[`docs/architecture.md`](docs/architecture.md) for the design and [`AGENTS.md`](AGENTS.md) for how
to work on it.

## Install

Requires macOS 13 or newer and Xcode 26.4 or newer (Swift 6.3).

```sh
scripts/install --cli
```

That builds `Switchboard.app`, puts it in `~/Applications`, registers it with Launch Services, links
`~/.local/bin/switchboard`, and opens it. It appears in the menu bar. To route links through it,
choose Set Default… in Settings → General, or System Settings → Desktop & Dock → Default web
browser.

Upgrading from the previous Swift app: delete its copy in `/Applications` so macOS finds only this
one. Settings and history carry over as they are.

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
