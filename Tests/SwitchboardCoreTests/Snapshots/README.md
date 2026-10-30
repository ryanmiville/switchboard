# Snapshot goldens

Golden PNGs for `SnapshotTests.swift`, drawn at 2x by `Snapshot.swift` on a developer's Mac. Each is named
`settings-<pane>-<light|dark>.png`.

- `make snapshots` renders every scene into `.build/snapshots` and compares it with its image here. A
  mismatch writes `<name>-actual.png` and `<name>-diff.png` (changed pixels in red) to
  `.build/snapshots/failures`.
- `SNAPSHOT_RECORD=1 make snapshots` rewrites these files. Review them before committing.
- A scene with no golden records one and fails once, so every new image gets looked at.

The images depend on the macOS version and the Mac's appearance settings, such as the accent colour and
when scroll bars show. CI renders the scenes without comparing them and uploads the images as the
`snapshots` artifact. Re-record after a macOS update that changes how controls draw.

The window is never shown or focused, so controls draw in their inactive style.
