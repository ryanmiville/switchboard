# Switchboard RS

A personal URL router, being rewritten in Rust with a [Rune](https://github.com/anomalyco/rune) UI.
Set as the default browser, it opens each link in a Chromium browser profile chosen by ordered rules.
The `switchboard-rs` command inspects and changes everything the app can, with `--json` output for
agents.

Status: in progress on the `rune-rewrite` branch. The core and the CLI work; the app is next. The
Swift app on `main` is the shipped version until this replaces it.

- Design: `docs/rewrite/architecture.md`
- Working in this repository: `AGENTS.md`
- Checks: `scripts/check`
