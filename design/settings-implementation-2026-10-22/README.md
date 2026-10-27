# Implemented Settings UI

Native screenshots from an isolated preview of the production views, using temporary configuration and fake browser bundles. No personal configuration, login-item registration, global shortcut registration, or browser delivery was exercised by the preview. The installed application was not replaced.

- `general.png`: grouped Opening links, Quick Switch, and Startup settings.
- `routing.png`: native rule table, default destination, and live URL preview.
- `quick-switch.png`: shortcut recorder and favorite destinations.
- `edit-rule-sheet.png`: draft rule editing with Cancel and Done.
- `routing-dark.png`: system Dark Mode appearance.
- `profile-recovery.png`: an unavailable profile, visible recovery actions, and scrollable settings.

## Verification

`make verify` passed: formatting, 70 tests in 12 suites, Debug and Release builds for both architectures, bundle checks, and whitespace checks.

New regression coverage checks draft isolation/cancellation, committing edits in place and adding only once, stale-draft rejection, browser-specific profile discovery and clearing, drag insertion ordering and identity, and clearing inherited profile selections when changing the default browser.

Native UI checks exercised adding and editing rules, Cancel, browser changes requiring a fresh profile, URL preview, arrow-button reordering, favorite add/remove, long profile names and URLs, narrow width, empty rules, missing favorites, Dark Mode, and repairing an invalid default profile. Recovery banners keep the Routing pane scrollable.

The automated pointer-drag check reached AppKit's native drag-session start, but the computer-use tool timed out before completing the drop. The insertion-order logic is regression-tested, and arrow-button reordering was exercised successfully. A manual drag-and-drop smoke check remains. Temporary drag instrumentation was removed; it was never added to production sources.

Actual browser delivery and installation remain separate from this UI change.
