# Switchboard CLI design

Status: implemented. [Implementation notes](#implementation-notes) lists where the code differs from this proposal.

## Goal

Let a coding agent (Claude Code, Codex, OpenCode, and so on) fix routing on request, for example "that last link opened in the wrong profile, make GitHub links for `acme` open in Chrome · Work". The agent should be able to:

1. Find out what just happened, without the user pasting the URL.
2. See why it happened: which rule matched and which browser/profile it chose.
3. Change the rules so the URL goes where the user wants, previewing the change first.
4. Confirm that the change worked.

The same commands should also be pleasant to use by hand.

## Decisions

- **CLI only, no MCP server.** Every agent we care about has a shell. A CLI with `--json` output, documented exit codes, and an agent skill covers the need with one less interface to maintain. If we later want routing fixes from an agent without a shell (Claude Desktop, the claude.ai apps), `switchboard mcp` can be added as a thin layer over the same operations.
- **Swift, sharing the app's code.** The CLI links the same `Config`, `Router`, and `BrowserProfiles` code the app uses, so validation and matching cannot drift. A Rust core was considered and rejected: the shared logic is a few hundred lines, and the hard parts (profile discovery, launching) depend on Apple APIs.
- **The config file stays the source of truth.** There is no daemon and no IPC. The CLI reads and writes `~/.config/switchboard/config.json` directly, whether or not the app is running. The app watches the file (see [App changes](#app-changes)).
- **One new dependency: [swift-argument-parser](https://github.com/apple/swift-argument-parser).** It is Apple's standard argument parser (used by SwiftPM and DocC), and it gives us subcommands, help, completion scripts, and strict validation. That is a clear payoff under AGENTS.md's dependency rule. The README's "no third-party package dependencies" line needs updating when it lands.
- **Routing history, on by default.** The app records the links it opens so an agent can find "that last link". See [History](#history).

The design borrows from agent-oriented CLIs, mainly [Rex](https://www.superlogical.com/rex/docs/automate/cli) from Superlogical:

- stable `--json` output on every command;
- a dedicated exit code for "not found or ambiguous", which never changes anything;
- a fixed resolution order for names;
- an agent skill that the CLI installs and keeps current itself.

## Packaging

- The binary is called `switchboard` and ships inside the app at `Switchboard.app/Contents/Helpers/switchboard`. It is versioned and installed with the app, so the two can never disagree about the config format.
- A new `make install-cli` target symlinks `~/.local/bin/switchboard` to the installed copy. Like the other install targets, it is never part of `make verify`.
- The binary is signed with the app (hardened runtime). `scripts/check-bundle.py` checks that it exists, that it is signed, and that it has the same architectures as the app.

### Build layout

- **Package.swift:**
  - adds the swift-argument-parser dependency;
  - adds a `SwitchboardCLI` library target holding the command definitions, plus a tiny `switchboard` executable target with only `@main`;
  - lets the test target depend on `SwitchboardCLI`, so commands can be parsed and run in-process.
- **Xcode project:**
  - adds a command-line tool target that compiles the core sources it needs plus the CLI sources, with a package reference to swift-argument-parser;
  - gives the app target a dependency on it and a Copy Files phase (code sign on copy) into `Contents/Helpers`.
- **Core split.** The CLI needs config, matching, profiles, history, and browser lookup, but none of the SwiftUI/AppKit UI (`TabPicker`, `GlobalShortcut`, `ConfigViewModel`, the app delegate). Split those core sources so the CLI can link them alone. The exact file layout is decided during implementation; Xcode's Sources phases and the `Makefile`'s format paths must follow.
- Browser discovery currently builds icons on the main actor. The CLI uses a variant without icons. The app keeps its icon version.

## Shared operations

The CLI commands are thin wrappers around a core `RuleOperations` service, tested directly.

- **`ConfigStore`** reads the config and records a *revision* (SHA-256 of the file bytes). It writes with a compare-and-swap:
  1. Re-read the file and compare its revision with the one the edit started from.
  2. On mismatch, fail with `conflict` and leave the file untouched.
  3. Otherwise, write with the existing atomic replacement.

  An advisory lock (`flock`) on a sibling lock file, shared with the app, closes the small window between the check and the rename.
- **Minimal edits.** A command changes only the rules it was asked to change. Unrelated rules, including legacy rules with display-name profiles, are not normalized or rewritten. Output uses the same `JSONEncoder` settings as the app, so the file's formatting is unchanged.
- **Validation matches the editor.** Profiles are resolved within the destination's browser. Directory identifiers win over colliding display names. Ambiguous display names are refused. Changing a rule's browser requires a profile for the new browser.

## Conventions

### Output

- Human-readable text by default.
- `--json` prints one JSON object on stdout: indented in a terminal, single-line when piped. Field names are stable and include full identifiers (browser paths, profile directory IDs), with display names alongside.
- Errors: human mode prints a message to stderr. With `--json`, stdout carries an error object instead:

  ```json
  {
    "error": {
      "code": "ambiguous_profile",
      "message": "“Ryan” matches 2 profiles in Google Chrome.",
      "candidates": [
        {"browser": "/Applications/Google Chrome.app", "profile": "Default", "profileName": "Ryan"},
        {"browser": "/Applications/Google Chrome.app", "profile": "Profile 3", "profileName": "Ryan"}
      ]
    }
  }
  ```

### Exit codes

| Code | Meaning | Example `error.code` values |
| --- | --- | --- |
| 0 | Success, including "nothing to change" | |
| 1 | The operation failed | `would_shadow`, `verification_failed`, `history_disabled` |
| 3 | Not found or ambiguous. Nothing was changed, and candidates are listed. | `profile_not_found`, `ambiguous_profile`, `browser_not_found`, `rule_not_found`, `history_entry_not_found` |
| 4 | The config can't be read or is invalid. The file was left untouched. | `config_unreadable`, `config_invalid` |
| 5 | Conflict: the config changed since the given or loaded revision | `conflict` |
| 64 | Invalid command line (swift-argument-parser's default) | |

### Global options

- `--json`
- `--config <path>`: defaults to `$SWITCHBOARD_CONFIG`, then `~/.config/switchboard/config.json`.
- `--history-file <path>`: defaults to `$SWITCHBOARD_HISTORY`, then the path in [History](#history).

Tests always pass both paths, so they never touch personal files.

### Resolving names

- **Browser.** In order: an app path (`/Applications/Google Chrome.app`), then a bundle identifier (`com.google.Chrome`), then a case-insensitive display name (`Chrome`, `Google Chrome`, `Helium`). Names are matched only against installed Chromium browsers that Switchboard supports. More than one match exits 3.
- **Profile.** Always resolved within one browser. In order: a directory identifier (`Default`, `Profile 1`), then a case-insensitive display name, accepted only when unambiguous. More than one match exits 3 and lists the candidates.
- **Rule.** By its 1-based position as shown in `rules list`. Positions shift when rules change, so mutating commands accept `--if-revision <rev>` (from any `--json` output) and exit 5 if the file changed since then.
- **History entry.** By ID, by an ID suffix of at least four characters, or with `--last` for the most recent entry.

## Commands

```
switchboard explain (<url> | --history <id> | --last)
switchboard route (<url> | --history <id> | --last) --profile <profile> [--browser <browser>]
                  [--match domain|exact|contains] [--value <pattern>] [--allow-shadowing] [--dry-run]
switchboard rules list
switchboard rules update <n> [--profile <profile>] [--browser <browser> | --default-browser]
                  [--match domain|exact|contains] [--value <pattern>] [--dry-run]
switchboard rules move <from> <to> [--dry-run]
switchboard rules remove <n> [--dry-run]
switchboard default [--browser <browser>] [--profile <profile>] [--dry-run]
switchboard profiles [--browser <browser>]
switchboard history [--limit <n>] [--full-urls]
switchboard history clear [--dry-run]
switchboard doctor
switchboard skill (setup | status | show | remove) [--agent <name>] [--dry-run]
```

Every command accepts `--json`, `--config`, and `--history-file`. Every mutating command accepts `--dry-run` and `--if-revision`.

### `explain`

Shows how a URL routes with the current config, without opening anything.

```
$ switchboard explain https://github.com/acme/api/pull/12
Rule 2 matched: domain github.com
  → Helium · Ryan (Default)
Also matches, but never reached: rule 5 (contains acme)
```

JSON output includes:

- `url` (redacted when it came from history, unless `--full-urls`);
- `matchedRule` (index, condition, value) or `null` for the default;
- `destination` (browser path and name, profile directory and name);
- `profileStatus`: `ok`, `missing`, or `ambiguous` (whether the destination profile still exists);
- `alsoMatches`: later rules that match but are shadowed;
- `revision`.

With `--history <id>` or `--last`, the output also includes where the link actually went at the time. That can differ from the current answer if the rules have changed since, or if the link was opened from the picker.

### `route`

The main command: "make this URL open here".

1. **Resolve** the target browser and profile. If `--browser` is omitted, the rule inherits the default browser (the `browser` field is left out), and the profile is resolved in the default browser.
2. **Build the rule.** `--match` defaults to `domain`. The value defaults to:
   - the URL's host for `domain` (pass `--value` to use a parent domain such as `github.com` instead of `docs.github.com`);
   - the full URL for `exact`;
   - nothing for `contains`, which requires `--value`.
3. **Place it.**
   - If the URL already goes to the target, nothing changes; exit 0 with `"changed": false`.
   - If a rule with the same condition and value (case-insensitive) exists, update its destination in place.
   - Otherwise, insert the new rule immediately before the rule that currently matches the URL, or append it if only the default matched.
4. **Check for shadowing.** If the new rule would prevent a later rule from ever matching, refuse with `would_shadow`, listing those rules, unless `--allow-shadowing` is given. Examples: a domain rule for `github.com` placed above one for `docs.github.com`; a contains rule whose value is inside a later contains rule's value.
5. **Verify.** Run the router on the edited config and check the URL now resolves to the target. If not, fail with `verification_failed` without writing.
6. **Write** with compare-and-swap, unless `--dry-run`.
7. **Report** the before and after destination, the rule added or changed and its position, and the new revision.

```
$ switchboard route --last --profile Work --browser Chrome --dry-run
Would add rule 2: domain github.com → Google Chrome · Work (Profile 2)
  before: Helium · Ryan (Default)  [default]
  after:  Google Chrome · Work (Profile 2)  [rule 2]
No changes written (dry run).
```

### `rules`

- `rules list` shows each rule's position, condition, value, browser (or "default browser"), profile directory and display name, and whether that profile still resolves. JSON output includes the revision.
- `rules update <n>` changes a rule's destination or pattern. Passing `--browser` or `--default-browser` requires `--profile`, matching the editor's rule that a browser change needs a new profile. The same shadowing and verification checks as `route` apply.
- `rules move <from> <to>` and `rules remove <n>` do what they say. Both report which URLs from recent history would now route differently, so the agent can catch accidental changes.

### `default`

With no options, shows the default destination. With options, changes it.

Changing the default browser also affects rules that inherit it. The command refuses (exit 3) if any inheriting rule's profile doesn't resolve in the new browser, and lists those rules. The user then fixes them with `rules update` first. Unlike the editor, the CLI never clears a profile choice silently.

### `profiles`

Lists installed, supported Chromium browsers (name, path, bundle ID) and each one's profiles (directory ID and display name). `--browser` limits the list to one browser. This is read-only, and it reads each browser's `Local State` file the same way the app does.

### `history`

Lists recent entries, newest first.

```
$ switchboard history --limit 3
a41f9c02  2m ago   https://github.com/acme/api/pull/12        rule 2 → Helium · Ryan
7d02be11  1h ago   https://accounts.example.com/callback?…    default → Helium · Ryan
c9e0aa54  1h ago   https://docs.google.com/document/d/…       picker → Google Chrome · Work
```

- URLs are redacted by default: the query string and fragment are replaced with `?…` and `#…`. `--full-urls` shows them.
- Agents normally pass `--history <id>` or `--last` to `explain` and `route`. That way the CLI uses the stored URL without printing it, which keeps tokens from magic links and OAuth callbacks out of agent transcripts.
- `history clear` deletes the history file.

### `doctor`

A read-only health check, also useful for agents debugging a failed link. It reports:

- the config path, whether the file parses, and its revision;
- the default destination and whether its profile resolves;
- each browser referenced by the config: installed or not, its `Local State` path, and its profile count;
- rules whose profile is missing or ambiguous, and rules that can never match because an earlier rule always wins;
- the history file's path, whether history is enabled, the entry count, and the last write error, if any;
- whether the CLI and the installed app are the same version.

### `skill`

Installs and manages a skill that teaches agents the workflow. Modeled on `rex skill`.

- **`skill show`** prints the guide, which is compiled into the binary, so upgrading Switchboard updates the guide. The guide covers:
  - the workflow: `history`, then `explain --last`, then `profiles`, then `route --last … --dry-run`, then `route`, then `explain --last` to confirm;
  - exit code 3 means ask the user to choose, never guess;
  - never edit `config.json` by hand;
  - prefer `--history`/`--last` over copying URLs.
- **`skill setup`** writes a short `SKILL.md` whose body tells the agent to run `switchboard skill show`. Locations:

  | Agent | `--agent` | Skill location |
  | --- | --- | --- |
  | Claude Code | `claude` | `$CLAUDE_CONFIG_DIR` or `~/.claude`, then `skills/switchboard/SKILL.md` |
  | Codex, OpenCode, Pi | `codex`, `opencode`, `pi` | `~/.agents/skills/switchboard/SKILL.md` (respecting `$CODEX_HOME` for Codex) |

  Setup finds agents by their config directory. `--agent` forces one. Setup is safe to repeat and reports each item as `installed`, `updated`, or `unchanged`. No hooks are installed: unlike Rex, Switchboard has no per-session context to inject.
- **`skill status`** reports each item as `current`, `outdated`, `missing`, or `foreign` (a `switchboard` skill this command didn't install, identified by a marker comment). Setup leaves foreign skills alone.
- **`skill remove`** removes only what setup installed.

## History

### What is recorded

The app appends one entry each time it opens a link, from rules or from the picker, whether the launch succeeds or fails:

```json
{"id":"a41f9c02","time":"2026-10-29T17:04:11Z","url":"https://github.com/acme/api/pull/12","source":"rule","rule":{"index":2,"condition":"domain","value":"github.com"},"browser":"/Applications/Helium.app","profile":"Default","profileName":"Ryan","result":"launched"}
```

- `source`: `rule`, `default`, or `picker`.
- `rule`: a snapshot of the rule's position, condition, and value at the time, since positions change later. Absent for `default` and `picker`.
- `result`: `launched`, or `failed` with an `error` message. Failed launches are recorded because "the link didn't open" is also something to fix.
- `id`: eight random lowercase hex characters.

### Storage

- `~/.local/state/switchboard/history.jsonl`, next to the XDG-style config location. The directory is created with mode `0700` and the file with `0600`.
- Append-only JSON Lines under the same advisory lock pattern as the config. Capped at 200 entries: when the file passes 400 lines, it is rewritten atomically with the newest 200.
- The CLI only reads history, apart from `history clear`.

### Behavior

- **Best effort.** A history write failure never blocks or delays opening a link, and never shows an alert. That would turn a working link into a failure. The error is logged with `os_log` and reported by `doctor`.
- **Short-lived launches.** A routing launch writes its entry synchronously before its idle-exit timer, so entries aren't lost when the app quits after opening a link.
- **Setting.** An optional `history` section in `config.json`, like `picker`:
  - omitted means enabled, so existing files keep loading;
  - `{"history": {"enabled": false}}` turns recording off, and the CLI's history commands then report `history_disabled`;
  - Settings → General gets a **Keep a history of opened links** toggle and a **Clear History** button.

### Privacy

History is a local log of the URLs you open, which can include tokens in query strings. The mitigations:

- file permissions;
- the 200-entry cap;
- URLs redacted in CLI output by default;
- `--history`/`--last`, so agents act on entries without seeing full URLs;
- the setting and `history clear`.

Nothing leaves the machine unless an agent reads it with `--full-urls`.

## App changes

These are prerequisites for the CLI, and worth doing on their own.

1. **Compare-and-swap saves.** `ConfigViewModel` saves through `ConfigStore` with the revision it loaded. On conflict it keeps the edits and shows the existing "keep edits and retry" style of error, with an option to reload from disk.
2. **Watch the config file.** Atomic replacement swaps the file, so the app watches the directory (or re-arms its watcher after a rename). On a change:
   - with no pending edits, reload silently, so routing uses the new rules immediately;
   - with pending edits, report the conflict as above, and never overwrite the external change silently.

   This matters because a resident app routes from its in-memory config. Without it, an agent's change would be ignored until restart, or overwritten by the next autosave.
3. **Record history** after each routing and picker launch, as described above.
4. **Add the history setting** to Settings → General.

## Testing

Tests follow AGENTS.md: temporary config, history, and `Local State` fixtures, fake browsers, and no real browser launches.

- **`RuleOperations`:**
  - `route` cases: append, insert before the matching rule, update in place, no-op, shadowing refused and allowed, post-edit verification;
  - profile resolution: directory ID beating a colliding display name, ambiguous names, the same directory ID in Chrome and Helium meaning different people;
  - cross-browser cases: a Chrome rule with a Helium default, legacy rules with no browser override, `default` refusing when an inheriting rule's profile is missing in the new browser.
- **`ConfigStore`:** conflict detection, unrelated rules preserved exactly, malformed files never replaced.
- **History:** append, trim, permissions, redaction, a disabled setting, the routing path still opening the link when the history write fails.
- **CLI:** parsing and running commands in-process with `--config` and `--history-file`, checking JSON shapes and exit codes.
- **Skill:** setup, status, and remove against a temporary home directory, including leaving a foreign skill alone.
- **App:** reloading on external change with and without pending edits, using the existing isolated `ConfigViewModel` setup.
- **Bundle:** `check-bundle.py` checks the embedded binary.

Not covered automatically: that the browser window actually opens in the right profile, and end-to-end agent use of the skill. Smoke-check those by hand.

## Rollout

1. App changes 1–2 (compare-and-swap saves, file watching), with the core split.
2. History recording (app changes 3–4).
3. The CLI: `explain`, `profiles`, `rules`, `route`, `default`, `history`, `doctor`, plus bundling and `make install-cli`.
4. `skill` commands and the guide.

## Out of scope

- An MCP server (see [Decisions](#decisions)).
- Opening URLs from the CLI. Launching a browser would make agent runs and tests open real windows. `explain` covers "where would this go".
- Editing picker favorites, the shortcut, or the login item.
- A daemon or IPC between the CLI and the app.

## Implementation notes

- **Build layout.** The command definitions live in `Switchboard/CLI` and compile into the `SwitchboardCore` package module, with a tiny `switchboard` executable target (`CLI/main.swift`). Xcode compiles the shipped tool as one module from those files plus the Foundation-only core files, so a separate `SwitchboardCLI` package module would have needed `public` or `package` access across the core, and `package` needs a package name that Xcode targets don't get by default. The Xcode target is named `SwitchboardCLI` (product `switchboard`), because target names that differ only by case collide on case-insensitive disks.
- **Browser discovery.** The CLI scans `/Applications` and `~/Applications`, plus any browser the configuration already names, instead of asking Launch Services, which needs AppKit.
- **Changing the default browser** is refused (exit 3, `inheriting_rules`) while any rule inherits the default browser, not only when an inheriting rule's profile is missing in the new browser: the same directory identifier can name different people in two browsers. The error suggests a `rules update` command per rule that keeps it where it goes now.
- **Extra values.** `profileStatus` can also be `unavailable` (the browser isn't installed or its profiles can't be read). Additional error codes: `ambiguous_browser`, `ambiguous_history_entry`, `inheriting_rules`, and `agent_not_found` (exit 3); `history_unreadable`, `profiles_unreadable`, and `write_failed` (exit 1); `invalid_argument` (exit 64, as a JSON error object when `--json` is given).
- **Rules.** `rules update` accepts `--allow-shadowing`, and refuses with `verification_failed` an update that would make the rule itself unreachable. `rules move` reports rules it makes unreachable instead of refusing. `rules update` and `default` also report recent links that would open somewhere else.
- **Small conveniences.** History IDs match by a prefix or a suffix of at least four characters. `--if-revision` accepts a prefix of at least eight characters. `history clear` works while history is off. `doctor` exits 0 and reports problems through `ok` and its `!` lines. The last history write error is kept in `history.jsonl.error` for `doctor`. Codex's skill goes to `$CODEX_HOME/skills` when that is set.

## Open questions

- Is 200 entries the right cap, and should old entries also expire by age?
- Should the CLI auto-retry a `conflict` once when no `--if-revision` was given? `route` recomputes from scratch, so a retry is safe for it. It isn't for position-based `rules` commands.
- Should `route` offer a `--parent-domain` shortcut, or is `--value` enough?
