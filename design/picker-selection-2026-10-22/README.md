# Quick Switch destination selection

Native previews of the production views using isolated fixture configuration and fake browser bundles with copied browser icons. Personal configuration and the installed app were not changed; no browser delivery was exercised.

- `settings.png`: destination checkboxes, Favorites Only, Show All, and separate favorite controls.
- `picker.png`: only the two selected favorites, browser icons, profile names, and separate Link to open / Open in labels.
- `long-settings.png`: realistic long profile names at the minimum 760-point Settings width in light appearance.
- `long-picker.png`: long profile names wrap while icons, shortcuts, stars, and footer actions remain visible.
- `empty.png`: empty selection with Choose Destinations recovery. Captured before the final spacing adjustment; the recovery action was verified to return to Quick Switch settings.

GUI checks exercised including and excluding a destination, Favorites Only, dark and light appearance, long names and URLs, minimum Settings width, empty selection, and its recovery action. No global shortcut or actual browser launch was exercised by the preview.

`make verify` passed: 77 tests across 12 suites, formatting, Debug and Release builds, both bundle checks, and whitespace checks. Regression coverage includes legacy JSON, explicit empty selections, persistence, browser-specific identities, newly discovered profiles staying unchecked, hidden favorites and shortcut numbering, stale hidden choices not launching, unavailable selected profiles/browsers, and routing configuration preservation.
