# Switchboard Next

A personal macOS URL router that opens links in Chromium browser profiles, chosen by rules you
define, with a `switchboard-next` command-line tool that can do everything the app can.

This branch (`swift-next`) is a from-scratch Swift port of the Rust rewrite's architecture. It is
in progress: the core is ported; the CLI and the SwiftUI app come next. See
[`docs/architecture.md`](docs/architecture.md) for the design and the order of work, and
[`AGENTS.md`](AGENTS.md) for how to work on it. The shipped app is on `main`.

## Development

```sh
scripts/check              # Everything CI runs, on macOS or Linux
scripts/check RouterTests  # Format, lint and file sizes, then only the matching tests
scripts/format             # Apply the checked-in formatting
```

Requires Swift 6.3 (Xcode 26.4 on macOS). The core and CLI also build and test on Linux;
`scripts/cloud-setup.sh` prepares a Linux cloud session.
