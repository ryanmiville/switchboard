# Switchboard Next

A personal macOS URL router that opens links in Chromium browser profiles, chosen by rules you
define, with a `switchboard-next` command-line tool that can do everything the app can.

This branch (`swift-next`) is a from-scratch Swift port of the Rust rewrite's architecture. It runs
next to the current Switchboard under its own name and settings folder
(`~/.config/switchboard-next/`), and offers to import the current app's settings. See
[`docs/architecture.md`](docs/architecture.md) for the design and [`AGENTS.md`](AGENTS.md) for how
to work on it. The shipped app is on `main`.

## Install

Requires macOS 13 or newer and Xcode 26.4 (Swift 6.3).

```sh
scripts/install --cli
```

That builds `Switchboard Next.app`, puts it in `~/Applications`, registers it with Launch Services,
links `~/.local/bin/switchboard-next`, and opens it. It appears in the menu bar. To route links
through it, choose it under Settings → General → Make Default…, or System Settings → Desktop & Dock
→ Default web browser.

## Development

```sh
scripts/check              # Everything CI runs, on macOS or Linux
scripts/check RouterTests  # Format, lint and file sizes, then only the matching tests
scripts/format             # Apply the checked-in formatting
scripts/bundle --debug     # Build the .app into .build/bundle without installing it
swift run Switchboard --snap out.png --scene routing   # Render a scene (see --list-scenes)
```

The core, CLI and editor model also build and test on Linux; `scripts/cloud-setup.sh` prepares a
Linux cloud session.
