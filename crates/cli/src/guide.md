# Switchboard routing guide

Switchboard is the default browser on this machine. It opens each link in a Chromium browser
profile chosen by ordered rules (the first match wins), or in the default destination when no rule
matches. The `switchboard-rs` command reads and changes those rules and the app's other settings. It
never opens links.

## Fixing "that link opened in the wrong place"

1. Find the link: `switchboard-rs history --limit 5`. Entries are newest first; the user usually
   means the most recent one.
2. See why it went there: `switchboard-rs explain --last --json` (or `--history <id>`). It shows the
   matched rule, the destination, and where the link actually went at the time.
3. Find the destination: `switchboard-rs profiles --json` lists each browser with its profiles, as
   directory identifiers (`Default`, `Profile 2`) and display names.
4. Preview: `switchboard-rs route --last --profile "<directory>" [--browser "<browser>"] --dry-run --json`.
   Check `before`, `after`, and `rule`, and tell the user what will change.
5. Apply: run the same command without `--dry-run`, adding `--if-revision <revision>` from step 4.
6. Confirm: `switchboard-rs explain --last` shows the new destination.

## Rules to follow

- Exit code 3 means a browser, profile, rule, or history entry wasn't found or was ambiguous.
  Nothing changed. Show the user the candidates and ask which one they mean. Never guess.
- Change settings through the CLI rather than editing `config.json`: the CLI validates profiles
  within each browser and refuses to overwrite changes made in the app since it read the file.
- Prefer `--last` and `--history <id>` to copying URLs. History URLs can contain sign-in tokens, so
  the CLI hides query strings and fragments. Don't pass `--full-urls` unless the user asks.
- Once you know a profile's directory identifier, pass that instead of its display name. The same
  directory identifier in two browsers can be two different people, so always name the browser you
  mean.
- Omit `--browser` to use the default browser. Pass it (a name like `Chrome`, an id, or a path) to
  send links to another browser.

## Choosing the pattern

`route` adds a domain rule for the URL's host by default. Domain rules also match subdomains.

- The whole site: `--value github.com` (instead of the host `docs.github.com`).
- Part of a site, such as one organization: `--match contains --value github.com/acme`.
- One exact URL: `--match exact`.

If a rule with the same match and pattern exists, `route` updates it; otherwise it adds the rule just
before the rule that matches the URL now.

## When a change is refused

- `would_shadow` (exit 1): the rule would stop later rules from ever matching. Prefer a narrower
  `--value`. Pass `--allow-shadowing` only if the user agrees.
- `verification_failed` (exit 1): the change wouldn't route the URL as asked, usually because an
  earlier rule matches first. Look at `switchboard-rs rules list` and consider `rules move` or
  another pattern.
- `conflict` (exit 5): the configuration changed since you read it, perhaps in the app. Start again
  from `explain`.
- `inheriting_rules` (exit 3): changing the default browser would move rules that inherit it into a
  browser whose profiles are different people. The error suggests `rules update` commands that keep
  each rule where it is; run them only with the user's agreement.
- `history_disabled` (exit 1): history is turned off. Ask the user for the URL.

## Commands

```
switchboard-rs explain (<url> | --history <id> | --last)
switchboard-rs route (<url> | --history <id> | --last) --profile <profile> [--browser <browser>]
                     [--match domain|exact|contains] [--value <pattern>] [--allow-shadowing] [--dry-run]
switchboard-rs rules list
switchboard-rs rules update <n> [--profile <profile>] [--browser <browser> | --default-browser]
                     [--match domain|exact|contains] [--value <pattern>] [--dry-run]
switchboard-rs rules move <from> <to> [--dry-run]
switchboard-rs rules remove <n> [--dry-run]
switchboard-rs default [--browser <browser>] [--profile <profile>] [--dry-run]
switchboard-rs profiles [--browser <browser>]
switchboard-rs history [--limit <n>] [--full-urls]
switchboard-rs history clear [--dry-run]
switchboard-rs history (on | off)
switchboard-rs picker (show | shortcut <keys> | favorite | unfavorite | destination | show-all)
switchboard-rs config
switchboard-rs doctor
```

Rules are numbered from 1, as `rules list` shows them. Positions shift when rules change, so pass
`--if-revision` to changing commands. `rules move`, `rules remove`, `rules update` and `default`
list recent links that would now open somewhere else; check them with the user. `doctor` reports
missing profiles, rules that can never match, and history problems.

## Output

Every command accepts `--json` and prints one JSON object on stdout. Errors look like
`{"error": {"code": "...", "message": "...", "candidates": [...]}}`.

| Exit | Meaning |
| --- | --- |
| 0 | Success, including "nothing to change" |
| 1 | The operation failed |
| 2 | Invalid command line |
| 3 | Not found or ambiguous; nothing changed; candidates listed |
| 4 | The configuration can't be read or is invalid; it was left untouched |
| 5 | The configuration changed since the given or loaded revision |
