# Agent-Ready Repositories

A setup guide for repositories where coding agents do most of the work: what to build on day one,
how to structure the code and docs, and which rules to enforce so agents stay fast without breaking
things.

**How to use it.** Start with the [day-one checklist](#day-one-checklist). Each item links to the
section that explains what to build and why. [Templates](#templates) are at the end. Take what fits
the project and skip what doesn't (a CLI has no screenshots, a library has no deploys). You can also
hand this file to an agent that is setting up a new repository and ask it to follow it.

---

## Why agents need a different setup

Agents are fast, never tire, and will happily run a command a hundred times. They also have four
weaknesses that a repository can make up for:

1. **They start every session cold.** Whatever isn't written in the repo is forgotten.
2. **They can't see unless you give them a way to look.** An agent can't glance at a window or hear
   a sound. It can read files.
3. **They over-claim.** "Added a test" becomes "verified" in the summary, and "should work" becomes
   "works".
4. **They take any shortcut the rules don't forbid.** A sentence in a doc is a suggestion. A failing
   check is a rule.

Several agents often work at once, too, so anything that funnels every change through the same lines
of the same file becomes a collision point.

The practices below answer those weaknesses: memory in files, eyes through headless tooling, exact and
fast checks, rules enforced by machines, a structure that keeps parallel work apart, and autonomy
written down.

## Principles

1. **Safety comes from checks.** If a person has to read code to know a change is safe, that person is
   the bottleneck. Build checks that answer in seconds, and let the code optimize for correctness and
   speed of change.
2. **Enforce rules with machines.** Every rule sits somewhere on the
   [enforcement ladder](#the-enforcement-ladder). Push each one as high as it will go.
3. **Make everything observable.** Every state the product can be in should be reachable, renderable
   and dumpable from a command, with no person and no display.
4. **Write for the next session.** Docs, commits, comments and test names are the only memory an
   agent has. Write them for a reader who knows nothing.
5. **Say what was verified.** Keep "implemented", "has a check", "check passed" and "someone saw it
   work" apart, everywhere.
6. **Keep parallel work apart.** Small files, one file per change, and features that plug in with one
   line.
7. **Make autonomy explicit.** Write down what an agent may do without asking, and the few things it
   must ask about.
8. **Every exception carries a reason.** That covers allowlists, lint suppressions, size exceptions and
   ignored security advisories.

## Day-one checklist

**Repository basics**

- [ ] One instruction file (`AGENTS.md`) under ~150 lines. Any tool-specific instruction file is a
      one-line pointer to it. See [The instruction file](#the-instruction-file).
- [ ] One `check` command that runs exactly what CI runs. See [The check loop](#the-check-loop).
- [ ] CI runs that command on every push and pull request. See
      [The enforcement ladder](#the-enforcement-ladder).
- [ ] Toolchain versions and dependencies pinned, with the lockfile enforced in CI.
- [ ] Strict lint configuration: warnings are errors, ambient state is banned. See
      [Lint rules](#lint-rules).
- [ ] A pre-commit hygiene check for secrets, local paths and scratch files. See
      [Secrets](#secrets).

**Seeing and checking**

- [ ] A headless render or structured dump of every screen or output, by name. See
      [Give agents eyes](#give-agents-eyes).
- [ ] A fake clock and seeded randomness, injected everywhere.
- [ ] A mock backend for every external system, chosen by an environment variable. See
      [Real systems](#real-systems).
- [ ] Snapshot tests with a "bless" switch. See [Oracles](#oracles-fast-exact-checks).
- [ ] Tests named as sentences.

**Parallel work**

- [ ] A file-size limit with a ratchet. See [Ratchets](#ratchets).
- [ ] A changelog written as one file per change. See [Many agents at once](#many-agents-at-once).
- [ ] Gitignored filenames for agent handoff notes.

**Memory**

- [ ] A plan or roadmap, a feature map, and a decisions folder, each with one job. See
      [Memory](#memory-documentation-that-outlives-sessions).
- [ ] A commit convention: one change, one line, area first, task ID at the end.

**Trust**

- [ ] CI and release configuration owned by a named person, and build jobs that hold no secrets. See
      [Trust boundaries](#trust-boundaries).
- [ ] An autonomy section in `AGENTS.md`. See [Autonomy and workflow](#autonomy-and-workflow).

---

## The instruction file

One file that every session reads first. Name it `AGENTS.md`, the name most agent tools read. If a
tool insists on its own filename, make that file a one-line pointer to `AGENTS.md` (some tools accept
a file containing only `@AGENTS.md`), so there is one source of truth.

### What goes in it

| Section | What it holds | Why |
|---|---|---|
| What this is | Two or three lines | Context for every decision |
| Layout | One line per top-level folder or module: what lives there | A map, so the agent doesn't spend its first minutes exploring |
| Commands | The exact check, test, build and run commands, ready to copy, including how to run a subset | Nothing gets guessed |
| Seeing the product | How to render or dump each screen or output headlessly, and the list of named scenes | UI changes get reviewed from images |
| Change rules | Branching, commit style, changelog, file limits, what must be updated together | Conventions every change follows |
| Autonomy | What to do without asking, and what to ask about first | Removes the biggest source of both hesitation and overreach |
| Never | Hard prohibitions: real devices, production data, history rewrites, secrets | Short and absolute |
| Read before changing | "Read `docs/sync.md` before changing sync" | Depth lives elsewhere |
| Current constraints | Freezes and migrations in progress, with dates | Time-bound rules, removed when they end |

### How to write it

- **Give each rule its reason, in one clause.** For example: "`main` is fast-forward only: consumers
  pin its commits, so a rewrite breaks every consumer's build." The reason lets an agent handle cases
  the rule didn't list, and stops it from applying the rule where it does harm.
- **Keep it about how to work.** What the product does belongs in the
  [feature map](#the-feature-map), and why it's built this way belongs in decision notes. A guide that
  grows into a behaviour spec costs its full size in context every session. Aim for under ~150 lines,
  and move sections out once it passes ~300.
- **Point to other docs instead of copying them.** Link to the document that owns a topic.
- **Tell agents how to read output.** "Read the check output whole; failures are summarised at the
  end" stops an agent from piping it through a filter and missing the failure.
- **Leave out machine-specific paths** such as home folders and private tool locations. They break for
  everyone else and leak in public repositories.
- **Treat it as code.** A change to the agent instructions changes what every future session does.
  Review it like a CI change, and flag it in your
  [agent pull-request policy](#agent-pull-request-policy).

## The check loop

The check command is the agent's main feedback signal. Make it fast, exact and easy to read.

- **One command, the same as CI.** `scripts/check` (or `make check`, `npm run check`) runs formatting,
  linting, type checks, tests and the dependency policy, and CI runs the same steps. If the two
  differ, agents pass locally and fail remotely.
- **Filterable.** `scripts/check <filter>` runs formatting plus only the matching tests, for the inner
  loop.
- **One exit code per stage**, such as 10 for formatting, 11 for lint and 12 for tests. The agent knows
  what failed without parsing anything.
- **Isolated tests with timeouts that name them.** A hung test should be killed and reported by name,
  never stall the run silently. If your stack has a test runner that gives each test its own process,
  use it.
- **A summary at the end.** Print the failures last, where an agent looks.
- **Fast paths for tests only.** Make slow-but-correct things fast in test builds, through switches
  that release builds ignore: a cheap key-derivation setting, a loopback-only network, a tiny model.
  List them in `AGENTS.md`.
- **Scripts that refuse misuse.** A benchmark script should refuse an unoptimized build. A script that
  needs a tool should check for it and print the install command.
- **Self-documenting scripts.** The header comment is the usage text, and `--help` prints it.
- **Know your build's cost centres.** If every test executable re-links the whole project, put each
  package's tests into one executable. Write down where new tests go, especially if a misplaced file
  would silently never run.

## Give agents eyes

An agent can only judge what it can read. Give every output of the product a form an agent can
inspect, produced by the same code that ships.

### For anything with a UI

- **Headless rendering.** A flag that renders any named state to an image file using the production
  renderer, with no window and no display. Machines without a GPU use a software renderer.
- **Structured dumps.** A flag that writes the element tree as JSON: identifier, role, text, position
  and size, colours, opacity, and hover or press state. Tests and agents can then assert on "the Save
  button" instead of a pixel.
- **Named scenes.** Every screen and every state worth seeing is registered by name with fixture data
  and fake services: empty, loading, error, long text, both themes. A `--list-scenes` command prints
  them, and `AGENTS.md` lists the important ones.
- **Scripted input by element ID.** A JSON script of taps, keys, drags and typing that targets elements
  by stable key instead of coordinates, so scripts survive layout changes.
- **A controllable clock.** Run on a virtual clock so animations and timers are deterministic. Render
  at an exact time (`--at 0.4`) to see a frame mid-animation.
- **Per-frame traces.** Write each element's position, size and opacity, frame by frame, to a
  line-delimited file for motion and performance analysis.
- **Recordings as evidence.** Frame strips or video rendered from a script, so a change can be shown
  to a person.
- **A built-in storybook.** Every component and screen can be browsed inside the running app in debug
  builds, and opened from tests.
- **A visual inventory script.** One command renders every scene in every theme into a folder. Run it
  before and after a change, or a dependency bump, and compare the folders.

### For everything else

- **Golden output.** Snapshot tests of what CLIs, generators and APIs produce.
- **Status and control commands.** `app status --json`, plus commands that drive the running program.
  Commands should be idempotent, with documented exit codes and a versioned protocol.
- **Documented logs.** Say where logs live, what each file holds, and in what format.

### Examples are tests

Every code example in the docs is either compiled and run as a test or cut from the source at build
time (see [Docs that fail the build](#docs-that-fail-the-build)). An example an agent copies should be
code that passes.

## Oracles: fast, exact checks

Ask questions that have exact answers. "Does it look right?" needs a person. "Do these two renders
match to within two colour levels?" doesn't.

### Snapshot (golden) tests

- Snapshot text structures (trees, JSON, generated code) as well as images.
- Capture both themes, and the sizes that matter.
- One switch (`UPDATE_GOLDENS=1`) rewrites the snapshots. The rule in `AGENTS.md`: regenerate in the
  same change, look at every changed snapshot, and commit them together.
- When CI fails a snapshot, upload the actual outputs as an artifact, so an agent on another operating
  system can download and inspect them.
- If rendering differs across platforms, run image snapshots on one platform only, and say which.

### Counts beat timings

Measure performance by counting things: allocations, instructions, queries, rendered elements, layout
passes, bytes. Counts are exact, repeatable and bisectable. Wall-clock times are none of these.

- A counting memory allocator in tests can assert that a steady-state loop allocates nothing.
- An instruction-counting profiler can compare two revisions on the same machine.
- When you do need wall-clock time, use an optimized build and paired, alternating runs. Compare
  medians, keep the outliers, and say what the number leaves out.

### Reference implementations

For hard, performance-critical code, keep a slow version that is obviously correct. Generate inputs,
run both versions, and compare them within a documented tolerance. When they differ, shrink the input
to a minimal case and commit it to a regressions folder that replays on every run. The fast version can
then be as clever as it needs to be.

The same idea works for ports: render the original and the port side by side and score the difference.

### Property tests and deterministic simulation

For concurrency, sync and distributed protocols:

- Run several simulated nodes in one process, with real storage and the real protocol code.
- A seeded scheduler picks message order, chunk sizes and delays. Use no real sockets, sleeps or wall
  clock.
- Inject faults as actions: crash and reopen, partition, heal, failed write, cut connection.
- Check properties after every step (durability, convergence, confidentiality), not just at the end.
- On a failure, print the seed, the full action list and a shrunk action list. One environment
  variable replays a list, and another sets how many seeds to search.
- Run the same trace twice and compare a digest, to prove the simulation itself is deterministic.

An agent can then reproduce a race condition with one command.

### Completeness tests

Tests of the form "every X has a Y" catch the most common agent mistake, which is changing one surface
and forgetting its siblings. For example:

- every persisted setting has a CLI command;
- every translated string exists in every language;
- every scene renders in both themes;
- every scene stops requesting frames once it is idle;
- every storybook entry opens from its link;
- every bundled theme parses.

Write one whenever two lists have to stay in step.

### Behaviour gates

Turn quality bars into tests that fail:

- idle means idle: no timers, frames or wake-ups once things settle;
- motion has no pops, jumps or overshoot (record per-frame positions and check them against rules);
- interactions are instant: switching panes lands in one frame.

Every allowlist entry for a gate needs a reason, and the gate should report entries that no longer
match anything.

### Fixture corpora

- **A synthetic corpus in CI.** One small fixture per pattern you support, such as one demo page per
  sign-in flow or one file per format quirk. Every fixture must pass.
- **A real-world sweep outside CI.** A tool that runs against hundreds of real inputs and writes a
  report ranked by failure pattern, with a before/after comparison mode. It is too slow and flaky for
  CI, and invaluable before a release.

## The enforcement ladder

Every rule lives on a rung. Rules on the higher rungs hold, and rules on the lower rungs drift.

| Rung | Example | Holds? |
|---|---|---|
| Type system or compiler | A test builds a public type with every field listed, so adding a field breaks it | Always |
| Lint, with warnings as errors | Reading the clock outside the clock module is banned | Always, if CI runs the linter |
| Tests in CI | Completeness tests, snapshot tests, behaviour gates | When CI runs on every change |
| A build that fails | Docs code samples extracted from the source | When that build runs |
| A script someone has to remember | A size check, a hygiene grep | Mostly |
| A sentence in a doc | "Keep lists sorted" | Drifts |

Two lessons from real projects:

- **Put every check script in CI.** In one project, rules that only scripts checked, and only when an
  agent remembered to run them, ended in unsorted lists the guide said must be sorted, and a stray
  scratch file committed to the root.
- **A project that fixes forward still needs one CI test job.** Merging once the code compiles is a
  fair speed trade early on. Merging with no test run at all means nothing catches what an agent
  breaks.

### Lint rules

- Warnings are errors, in CI and in the check command.
- Ban ambient state outside one owning module, with a reason message the agent sees when it trips the
  rule:
  - environment variables: read them in the config module at startup;
  - wall-clock time: use the injected clock;
  - randomness: use the seeded source;
  - network calls and process spawning: go through the one module that owns them.
- Allow shortcuts such as panics and debug prints in tests only.
- Every lint suppression carries a comment saying why.

These bans are also what make deterministic tests possible, so they double as test infrastructure.

### Compile-time contracts

If consumers build some of your public types directly, add a test that builds each of them with every
field listed. Adding a field then breaks your repo first, before it breaks theirs. Prefer to grow
public APIs by adding things (new builder methods, new optional parameters), and list the types
consumers build directly in `AGENTS.md`.

### Dependency policy

Use a dependency checker that allowlists registries, git sources and licences, denies wildcard
versions, and requires a reason for every ignored security advisory.

### Ratchets

A ratchet is a limit plus a list of exceptions whose ceilings can only go down.

- **File size:** a soft warning around 800 lines and a hard error around 1,500. Files that were already
  larger are listed with their current size as a ceiling. The ceiling drops automatically as the file
  shrinks, and goes up only with an explicit flag.
- **Anything else that creeps:** the same pattern works for warning counts, bundle size, binary size,
  startup time and test duration.

A ratchet stops growth without forcing a big cleanup up front.

### Docs that fail the build

The docs pull their code samples out of source files by marker at build time. If a function is
renamed, the docs build fails with the snippet's name, so no example can drift away from the code.

### Generated files

Regenerate lockfiles, bindings and generated code with the project's own tools, never by hand, and
check in CI that they are current.

## Many agents at once

- **Small files.** A size cap exists to stop god files and edit collisions: two agents working in one
  8,000-line file will eventually edit the same region. Don't split a file that reads fine as one
  piece just to hit a number.
- **One file per change for append-only files.** For the changelog, release notes and migration notes,
  each change adds its own file, such as `changelog/unreleased/<date>-<slug>.md`. At release, a script
  merges the files into the main document, ordered by first commit, and deletes them.
- **One item per line, sorted,** in module lists, export lists, registries and config arrays, so two
  additions rarely touch the same line.
- **Features own their state.** A feature holds its own state, keys and registrations, and plugs in
  with one line. New state goes in the subsystem that owns it, not in a central object everyone edits.
- **Move first, then change.** Moving code into a new module is its own commit or PR, landed before
  the behaviour change, so the move and the change can't conflict.
- **One worktree per agent.** Remove it when its PR merges. Say in `AGENTS.md` how agents coordinate
  changes to shared files.
- **Handoff notes never get committed.** Pick fixed names for agent-to-agent notes (for example
  `REVIEW-TO-PARENT.md` and `*-FROM-PARENT.md`) and gitignore them.
- **Shared machines behind a wrapper.** Scripts accept a command-prefix variable (`CHECK_WRAP=…`) so a
  run can hold a lease on a shared build machine or queue.
- **A merge queue.** Batch a few PRs, verify them together, then land them. Optionally build and install
  the result on the owner's machine, so every landed change gets used.
- **Unfinished features behind experiment flags.** Unfinished work lands on the main branch behind a
  named flag that is never on by default, debug builds included. Gate it where the feature's work
  starts (a worker, a thread, a background task), not only in the UI. Remove the flag when the feature
  ships or is dropped. Agents can then merge small pieces continuously without half-built features
  leaking out.

## Memory: documentation that outlives sessions

Give each document one job, and say which document owns which question.

| Document | Owns | Updated |
|---|---|---|
| `AGENTS.md` | How to work here | When a convention changes |
| `PLAN.md` or `ROADMAP.md` | Direction, principles, targets, future work | Before work that changes direction |
| Feature map (`docs/features/`) | What exists: user-facing behaviour, entry points, checks, gaps | In the same change as the behaviour |
| Decision and research notes (`docs/decisions/`) | Why things are built the way they are | When a decision is made |
| Module READMEs | What a module does today, and where it differs from the plan | With the module |
| `CHANGELOG.md` | What changed, for the people and agents upgrading | With every change that affects consumers |

Where two documents overlap, say which to update first ("update the plan first, then the site").

### The feature map

- Organize it by what a user can do, not by code module.
- Give each behaviour a stable ID (`recording.cancel`) that tests, issues and commits can refer to.
- For each behaviour, record how to reach it, what happens (a small tree or flow), the source files,
  the tests that cover it (by name), what was observed, and the gaps.
- Read the relevant entry before designing, changing, debugging or reviewing a feature, and update it in
  the same change.
- Keep an index. Give a capability its own file once it needs its own verification steps.

### Evidence levels

Use these four terms consistently:

1. **Implemented:** the code exists.
2. **Has a check:** a test exists. A test's existence is not a passing run.
3. **Check passed:** with the date, platform and conditions.
4. **Observed end to end:** a person, or a run in a real environment, saw it work, on stated hardware.

Record what wasn't checked, for example "no physical-device test was run" or "a virtual display doesn't
prove behaviour on a real desktop". Never rewrite an expected outcome to hide a regression; record the
defect instead. Label every number as a **target** or a **measurement**, and say how it was measured.

### Research and decision notes

Open each note with a short header:

```
Reader: the next agent changing <area>, or someone deciding <question>.
Status: proposal | built | superseded by <note>. <Date>.
Re-run <command> before changing <area>.
```

Then give the question, the evidence, the verdict, and the commands that reproduce every number. For a
design proposal, write an adversarial critique as a separate, dated note, then a revised proposal. End
with open questions. Record each decision with its date, who made it, and the alternatives rejected,
each with its reason.

### A changelog for upgraders

The people upgrading, often agents, read the changelog to find out what to change. Each entry:

- opens with a bold one-sentence summary;
- says what changed in behaviour and in the API;
- starts with **Breaking:** for a breaking change, and gives the exact steps to migrate;
- ends with "Nothing changes for code that doesn't use it" for an addition.

### Commits

One change per commit, described in one line: area first, then the behaviour, then the task or issue
ID.

```
overlay: read the panel's occlusion once per loop (t834)
Fix #469: report dictation status with the microphone released (#470)
```

### Tests and comments

- Name tests as sentences, such as `a_bare_left_click_is_refused_but_other_buttons_are_not`. The name
  works as the spec, and the docs can cite it.
- Comments state invariants and intent for the next reader. They don't narrate what the code does.

## APIs and errors that teach

- **Errors name the problem, the caller's location and the fix.** For example: "Duplicate key `card`
  under `cards`: first at view.ext:41, again at view.ext:42; give siblings unique keys." Capture the
  caller's location in debug builds.
- **Warn once** per call site or key, so logs stay readable.
- **Recover where it's safe.** Rename the duplicate and keep drawing, as well as warning. The agent keeps
  a working program and gets the message too.
- **Document gotchas where they bite,** in the docs of the function that has them.
- **One way to do things.** Prefer small, explicit APIs. Avoid custom DSLs and deep generic
  abstractions, whose errors an agent has to reverse-engineer.

### Rules against agent over-engineering

Agents tend to add abstraction layers, compatibility shims and parallel helpers. Rule these out in
writing:

- Add an abstraction (an interface, a plugin point, a seam) only when there are two real
  implementations or a current test needs to substitute one. Don't add seams for roadmap items.
- Don't add compatibility shims for internal APIs: change the API and update its callers.
- Extend an existing helper instead of adding a parallel one. Never keep two helpers for the same job.
- Don't write literals where a design token or config value exists (colours, spacing, timeouts).
- Keep modules deep: callers shouldn't have to coordinate a module's internals.

## Real systems, secrets and trust

### Real systems

- **Mock backends behind a contract.** Each external system (hardware, OS services, network APIs) has
  a contract module, a real backend and a mock backend, chosen by an environment variable. Every
  headless scene runs on the mocks.
- **Never touch the real thing.** Say in `AGENTS.md`:
  - never change real devices, accounts or settings without restoring them;
  - never run a second instance on someone's machine;
  - send only read-only requests to live services;
  - keep fixtures and snapshots synthetic, never real user content.
- **Test builds get their own identity.** A separate app identifier and data folder, so a test build
  can never read or overwrite real data. Test builds never update themselves.
- **CI fakes the hardware.** Virtual displays, headless compositors and browsers, virtual audio
  devices and loopback networks let CI exercise real input, capture and output paths end to end. Write
  down what the fakes don't prove.

### Secrets

- Secrets go into a command's environment or a private file. Never put them in command-line arguments,
  logs or an agent's transcript.
- Reading a secret into a transcript should be deliberate, rare and logged.
- Issue templates ask reporters to redact logs and screenshots.
- A pre-commit check searches staged changes for secrets, home-folder paths, internal hostnames and
  session IDs.

### Trust boundaries

Agents can change code freely as long as the code that holds secrets is out of their reach:

- CI and release configuration is owned by a named person, through code owners and branch rules.
- Build and test jobs hold no secrets or identity tokens.
- Signing and publishing jobs check out only a locked folder of scripts, treat build outputs as data,
  and verify checksums.
- Third-party CI actions are pinned to an exact commit hash.

### Agent pull-request policy

For pull requests opened by agents or an automated pipeline, run a deterministic diff classifier (no
AI involved) from the **base** branch, so a patch can't change its own policy.

| Tier | Triggers | Result |
|---|---|---|
| Person only | CI and release config, code ownership, signing, the updater and other trust code | Never merged automatically |
| Flagged | Dependency manifests and lockfiles, build scripts, packaging, deployment config, agent instruction files, tool config. New URLs or hostnames, process spawning, network APIs, unsafe or native code, long encoded blobs, invisible or bidirectional Unicode, reads of secret-named environment variables. Executable bits, symlinks, binary files. More than ~600 changed lines or ~25 files | Needs a strict reviewer's approval |
| Clean | Everything else | Merges once checks pass |

## Autonomy and workflow

- **Write the autonomy level down.** Pick one per project and say it plainly: "merge once checks pass"
  or, for a young project, "merge once it compiles, then fix forward". Then list the few things to ask
  about first: deploys that replace something live, releases, destructive operations, anything
  irreversible.
- **No fixed sleeps.** Wait on CI or a deploy with a command that blocks until it finishes and exits
  with its result. Don't end a turn while still waiting on something.
- **Start each round of work with dependency bumps.** For internal dependencies pinned to exact
  revisions:
  1. bump them to the latest revision;
  2. read the changelog since the old pin;
  3. adapt to breaking changes;
  4. run the checks;
  5. compare the visual inventory from before and after.

  If the dependency itself is broken, report it upstream instead of working around it.
- **Never rewrite history others pin.** Branches that consumers pin are fast-forward only. Rewriting
  published history deletes every revision consumers pinned.
- **Use issues as the input queue.** Issue templates collect the version, platform, environment and
  steps to reproduce. An automated pipeline can turn issues into pull requests: name each one after its
  issue, link the pipeline run, and gate it with the
  [agent pull-request policy](#agent-pull-request-policy).
- **Keep time-bound rules in one place.** Release freezes and migrations in progress go in a "Current
  constraints" section, and come out when they end.

## Make the product itself agent-operable

Your users have agents too. A product they can drive and configure through files and commands gets
better results from those agents.

- **A control CLI.** Provide `status --json`. Make commands idempotent (repeating one reports
  "unchanged" and succeeds), with documented exit codes and a versioned protocol. Add a test that fails
  when a setting has no command.
- **A config validator.** `app check <file>` loads the config exactly as the app does and reports every
  problem with file, line and column.
- **A headless preview of user config.** Render the user's theme or config from an isolated config
  folder, so their agent can check its work without touching the live setup.
- **Docs for your users' agents.** Write a guide addressed to coding agents ("everything needed to do X
  and check it without a display"). Package it as a skill. Have the app write instructions and type
  definitions into the user's config folder, and keep them current.
- **A site agents can read.** Serve the docs as a single Markdown document to agent user-agents and to
  requests with `Accept: text/markdown`, and publish an `llms.txt`.
- **Tiered access for AI callers** to anything sensitive. Listing and searching are free (and logged).
  Using a secret doesn't reveal it: the secret goes straight into a command. Reading or changing one
  needs an approval that requires physical presence, because an agent with screen control can click any
  button.

## Anti-patterns

- An instruction file that grows past a few hundred lines and loads into every session.
- Rules that live only in prose, or only in scripts that CI doesn't run.
- No CI test job.
- Machine-specific paths and private tool references in shared instructions.
- Rewriting history on a branch others pin.
- Docs that say "verified" where a test merely exists.
- Allowlist entries and lint suppressions without reasons.
- A central file or object that every feature edits.
- Fixed sleeps while waiting on CI.

---

## Templates

### AGENTS.md

````markdown
# <Project>

<One or two lines: what it is and who uses it.>

## Layout

- `src/<area>/`: <what lives here>.
- `src/<area>/`: <what lives here>.
- `docs/features/`: what the product does, by user capability. Read the entry before changing a
  feature, and update it in the same change.
- `docs/decisions/`: why things are the way they are.

## Commands

- Everything CI runs: `scripts/check` (exit codes: 10 format, 11 lint, 12 tests).
- A subset: `scripts/check <filter>`. Read the output whole; failures are summarised at the end.
- See a screen without a display: `<app> --snap out.png --scene <name>`. List scenes with
  `<app> --list-scenes`.
- Dump the element tree: `<app> --tree out.json --scene <name>`.
- Update snapshots: `UPDATE_GOLDENS=1 scripts/check <filter>`. Look at every changed file and commit
  them with the change.

## Changes

- Branch from `main` and open a PR. `main` is fast-forward only: <consumers> pin its commits, so a
  rewrite breaks their builds.
- One change per commit: `area: what changed (task-id)`.
- Anything a user or consumer would notice adds `changelog/unreleased/<YYYY-MM-DD>-<slug>.md` with one
  bullet.
- Files stay under 800 lines; `scripts/file-size` checks. Exceptions only go down. Move code to a new
  module in its own PR before changing it.
- Unfinished features land behind an experiment flag in `<file>`, off by default.
- <Rule>. <Its reason, in one clause.>

## Autonomy

- Merge your PR once its checks pass.
- Ask first before: <deploying X>, <releasing>, <anything destructive>.
- Wait on CI with `<watch command>`, never a fixed sleep. Don't end your turn while waiting.

## Never

- Touch real devices, accounts or data: use `<APP>_BACKEND=mock` and the scenes.
- Commit secrets, local paths, scratch files or handoff notes. Run `scripts/hygiene` before committing.
- Rewrite history on `main`.

## Read before changing

- Sync or networking: `docs/simulation.md`.
- UI: `docs/design-system.md`.

## Current constraints

- <A freeze or migration, with its date and who to ask. Remove it when it ends.>
````

### Tool-specific pointer file

```markdown
@AGENTS.md
```

### Feature map entry

````markdown
## Cancel a recording   <!-- id: recording.cancel -->

How to reach it: Escape while recording, or `app recording cancel`.

```
Escape while recording
├── nothing transcribed yet -> the recording is discarded, nothing is inserted
└── transcription already running -> it finishes, and its output is dropped
```

Source: `src/recording/cancel.<ext>`.
Checks: `escape_discards_an_unfinished_recording`, `a_cancelled_job_never_inserts_its_text`.
Observed: both passed in the full suite on 2026-10-25 (Linux container). A person confirmed it on a
real machine the same day.
Gaps: no test injects a cancel during output. Not run on <platform>.
````

### Research or decision note

```markdown
# NN. <The question, as a title>

Reader: the next agent changing <area>, or someone deciding <question>.
Status: <proposal | built | superseded by NN>. <Date>.
Re-run `<command>` before changing <area>.

## Question
## Evidence
(Every number says whether it is a target or a measurement, and how it was measured.)
## Verdict
## Rejected alternatives
(Each with its reason.)
## Open questions
## Decisions
(Date, who decided, and what.)
```

### Changelog fragments

```markdown
- **Breaking: `Widget.size` takes points, not pixels.** Divide existing values by the scale factor,
  or call `Widget.sizePx`. Snapshots of scaled windows change.
```

```markdown
- **`Client.retry(policy)` retries failed requests with backoff.** Requests that succeed the first
  time are unchanged. Nothing changes for code that doesn't call it.
```

### Check script

```bash
#!/usr/bin/env bash
# The local check loop. It runs exactly what CI runs.
#
#   scripts/check            format, lint, then every test
#   scripts/check <filter>   format, then only the matching tests
#
# Exit codes: 10 format, 11 lint, 12 tests.
set -uo pipefail
cd "$(dirname "$0")/.."

stage() { printf '\n==> %s\n' "$1"; }

stage "format"
<format-check-command> || exit 10

if [[ $# -eq 0 ]]; then
  stage "lint"
  <lint-command-with-warnings-as-errors> || exit 11
fi

stage "test"
<test-command-with-per-test-timeouts> "$@" || exit 12
```

### Hygiene check

```bash
#!/usr/bin/env bash
# Fails if staged changes contain secrets, local paths or internal hostnames.
set -euo pipefail
pattern='/Users/|/home/[a-z]|PRIVATE KEY|<internal-host-pattern>|<session-id-pattern>'
if git diff --cached -- . ':(exclude)scripts/hygiene' | grep -nE "$pattern"; then
  echo "hygiene: remove the lines above before committing" >&2
  exit 1
fi
```

### .gitignore additions

```gitignore
# Agent handoff notes
/REVIEW-TO-PARENT.md
*-FROM-PARENT.md

# Local scratch output
/scratch/
```
