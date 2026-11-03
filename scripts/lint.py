#!/usr/bin/env python3
"""Bans the calls that let code reach past its parameters: the real home folder, the environment,
the clock, starting processes, and handing links to the system.

    scripts/lint.py        check Sources/ and Tests/

Each rule names its owner: the one place that may make the call and pass the result in, so tests
can use a temporary home, fixed times and fake browsers. Other uses are listed in
scripts/lint-exceptions.txt as "<path> <rule> # <reason>". The reason is required, and an
exception that no longer matches anything fails, so the list stays true.
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXCEPTIONS = ROOT / "scripts" / "lint-exceptions.txt"
SOURCES = ("Sources/",)
EVERYWHERE = SOURCES + ("Tests/",)
# The Foundation-only targets, where links are routed and launched.
LINK_TARGETS = ("Sources/SwitchboardCore/", "Sources/SwitchboardCLI/", "Sources/SwitchboardEditor/")

# name: (pattern, directories, what to do instead)
RULES = {
    "home": (
        r"homeDirectoryForCurrentUser|NSHomeDirectory\(\)",
        EVERYWHERE,
        "take the home folder as a parameter, so tests use a temporary one",
    ),
    "environment": (
        r"ProcessInfo\.processInfo\.environment|\bgetenv\(",
        EVERYWHERE,
        "read the environment once, through Env.fromProcess() in a binary's entry point, and pass values in",
    ),
    "clock": (
        r"\bDate\(\)|\bDate\.now\b",
        SOURCES,
        "take the time, or a `now` closure, as a parameter, so tests are deterministic",
    ),
    "process": (
        r"\bProcess\(\)",
        SOURCES,
        "start browsers only through Launch.launch",
    ),
    "system-open": (
        r"NSWorkspace\.shared\.open\b|/usr/bin/open\b",
        SOURCES,
        "launch the browser executable through Launch.launch; the system's handler for a link "
        "may be Switchboard itself, and `open -a` drops profiles when the browser is running",
    ),
    "link-url": (
        r"\bURL\(string:|\.absoluteString\b",
        LINK_TARGETS,
        "keep a link as the String it arrived as and read it with Link; URL re-encodes characters",
    ),
}


def tracked_swift_files():
    out = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", "*.swift"],
        cwd=ROOT, check=True, capture_output=True, text=True,
    ).stdout
    return [line for line in out.splitlines() if line and (ROOT / line).is_file()]


def read_exceptions(errors):
    allowed = {}
    if not EXCEPTIONS.exists():
        return allowed
    for number, raw in enumerate(EXCEPTIONS.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        entry, _, reason = line.partition("#")
        fields = entry.split()
        where = f"{EXCEPTIONS.relative_to(ROOT)}:{number}"
        if len(fields) != 2 or fields[1] not in RULES:
            errors.append(f"{where}: expected '<path> <rule> # <reason>' with a rule from {sorted(RULES)}")
        elif not reason.strip():
            errors.append(f"{where}: {fields[0]} {fields[1]} needs a reason after '#'")
        else:
            allowed[(fields[0], fields[1])] = where
    return allowed


def main():
    errors = []
    allowed = read_exceptions(errors)
    used = set()
    for path in tracked_swift_files():
        lines = (ROOT / path).read_text(encoding="utf-8").splitlines()
        for name, (pattern, directories, instead) in RULES.items():
            if not path.startswith(directories):
                continue
            for number, line in enumerate(lines, 1):
                if line.lstrip().startswith("//") or not re.search(pattern, line):
                    continue
                if (path, name) in allowed:
                    used.add((path, name))
                    continue
                errors.append(f"{path}:{number}: [{name}] {line.strip()}\n    -> {instead}")
    for key, where in allowed.items():
        if key not in used:
            errors.append(f"{where}: {key[0]} no longer breaks [{key[1]}]; remove the exception")
    for error in errors:
        print(f"lint: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
