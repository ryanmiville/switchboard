# Switchboard Settings — 10 screenshot concepts

October 22, 2026. Static design exploration, using sample rules and profile labels. Production app files and personal configuration are untouched. The PNGs are mockup renders, not captures of an implemented redesign. All screenshots are 2400 × 1680 pixels.

Open `index.html` for a gallery with a full-size screenshot, tradeoffs, and a visual picker. Use the arrow keys, 1–9, or 0 for concept 10. `overview.png` is the contact sheet; `switchboard-settings-10-mockups.zip` contains all ten PNGs and the offline gallery.

| # | Direction | Best fit | Tradeoff |
| --- | --- | --- | --- |
| 1 | Familiar sidebar | Clear categories and an easy overview | Uses horizontal space for navigation |
| 2 | Toolbar panes | Conventional Mac preferences | Categories are on separate panes |
| 3 | Table + inspector | Growing rule collections and frequent edits | Wider, more technical window |
| 4 | Sentence rules | Readable rules with inline editing | Long text needs more width |
| 5 | Browser first | Understanding which profile owns which links | Global rule priority must stay visible |
| 6 | Focused cards | One expanded rule at a time | Fewer rules visible while editing |
| 7 | Compact utility | A small menu bar companion | Less room for help or many rules |
| 8 | Routing workbench | Frequent testing while changing rules | Testing consumes permanent space |
| 9 | Essentials | Defaults, login, and the shortcut on arrival | Rules are one click deeper |
| 10 | Sheet editor | A clean list with deliberate rule edits | The sheet interrupts comparison |

## Design basis

Applied Ryan's Apple Design, Emil Design Engineering, and Prototype skills, plus proportional visual checks from Break UI. Adapted them to a native Mac utility: system typography, SF Symbols, comfortable density, muted grouped surfaces, clear selection, stable category navigation, browser and profile shown together, explicit first-match order, and a test that previews the result without opening a browser.

The native macOS sections of Apple's current guidance are the main references:

- [Settings](https://developer.apple.com/design/human-interface-guidelines/settings): stable pane navigation, pane titles, disabled minimize/maximize controls, Command–Comma access, last-used pane restoration.
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos): comfortable information density, precision, and keyboard workflows.
- [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars): concise groups, meaningful SF Symbols, and the space cost of a sidebar.
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars): standard controls, deliberate grouping, restrained color, and a clear primary action.

The screenshots illustrate visual directions; they do not establish interaction behavior, resizing, accessibility, error handling, or actual browser delivery. A chosen direction would need those implemented and checked. Browser/profile directory identifiers are shown in detailed editors, while summary rows emphasize readable destination names.

## Reproduce

From the repository root, on macOS:

```sh
swift design/settings-exploration-2026-10-22/render.swift
python3 design/settings-exploration-2026-10-22/package.py
```

Packaging requires Pillow. The renderer uses AppKit only, reads the installed Chrome/Helium app icon resources when available, and uses an SF Symbol fallback otherwise. It does not launch the apps or read browser data. No installation or production build is needed.

## Visual checks

Reviewed all ten screenshots at readable scale. Corrected a table footer overlapping the final rule in concept 3. Checked the compact layout's actions, rule numbers, dark appearance, form labels, browser/profile pairing, and sheet boundaries. A complete stress test with long labels, empty and error states, enlarged text, and interactive resizing remains part of implementing a selected design.
