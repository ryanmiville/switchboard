<p align="center">
  <img src="icon_1024x1024.png" width="128" height="128" alt="Switchboard icon">
</p>

# Switchboard

A personal macOS URL router that opens external links in Chromium browser profiles based on rules you define.

## Requirements and installation

- macOS 13 or newer.
- Full Xcode 26.4 with command-line tools selected. Standalone Command Line Tools are insufficient for the app build.
- A supported Chromium browser. Helium has been used with the real app; automated fixtures cover profile discovery for Chrome and its channels, Chromium, Brave, Edge, Vivaldi, and Helium.

Run `make install` to build Release, copy it to `/Applications/Switchboard.app`, and register it with Launch Services. Use `make debug-install` for Debug. Then select Switchboard under **System Settings → Desktop & Dock → Default web browser**.

Installation does not change your default-browser selection automatically.

## Configuration

Open Switchboard, then choose **Settings** from its menu-bar icon, or press **Command–Comma** while its window is active. Settings remembers the last pane: **General** groups startup and destination summaries, **Routing** contains the default browser/profile, ordered rules, and URL preview, and **Quick Switch** contains the global shortcut and favorite destinations.

Use **Add Rule** or select a rule and choose **Edit Rule…** to open its sheet. Double-clicking a rule or pressing Return also edits it. Changes stay in the sheet until **Done** or **Add Rule**; **Cancel** leaves the configuration untouched. Each rule can use the default browser or a different Chromium browser, with its own profile. For example, work links can open a Google Chrome profile while everything else opens Ryan in Helium. Drag rows or use the arrow buttons to change priority: the first match wins. The URL preview shows the selected browser and profile without opening anything.

Changing a rule’s browser clears its profile choice so you can select a profile belonging to the new browser. Profile directory names can be identical across browsers, so they are never treated as a shared identity.

Changing the default browser also clears its default profile and the profile choices of rules that inherit that browser. Rules with an explicit browser keep their existing destination. Choose profiles for the new browser before the configuration can be saved.

- **Contains** matches a substring anywhere in the complete URL, including its query string.
- **Exact** matches the complete URL.
- **Domain** matches a host and its subdomains. For example, `github.com` matches `docs.github.com`, but not `github.com.example.com` or a query parameter mentioning GitHub.

All matching is case-insensitive. Empty patterns are ignored. Unmatched URLs use the configured default browser and profile.

Settings are saved automatically after a short delay. Pending changes are saved before quitting or routing a link from an open editor. Loading and saving errors appear in the editor with recovery actions. Invalid configuration is left untouched, and failed saves retain changes in the window for retry.

The configuration file is `~/.config/switchboard/config.json`:

```json
{
  "browser": "/Applications/Helium.app",
  "defaultProfile": "Default",
  "routes": [
    {
      "condition": "domain",
      "value": "gitlab.com",
      "browser": "/Applications/Google Chrome.app",
      "profile": "Profile 2"
    }
  ]
}
```

The top-level `browser` and `defaultProfile` define the default destination. A rule’s optional `browser` overrides the default browser. Older rules without it keep using the top-level browser, so existing files continue to work.

Profiles are saved as Chromium directory identifiers, while the editor displays friendly names alongside them. Profiles are discovered and validated within each destination’s browser. Older files containing display names are resolved when unambiguous and converted to directory identifiers when saved. Missing or ambiguous selections require choosing a profile in the editor.

A link launches the selected browser executable directly so profile arguments work even when the browser is already running. A temporary routing launch exits shortly afterward. An existing editor stays open. If a link cannot be launched, Switchboard offers settings or a copy of the link instead of silently choosing another browser.

## Open the current browser tab in another profile

Opening or reopening Switchboard starts its menu bar and shortcut without opening Settings. Switchboard stays out of the Dock, including while Settings or the picker is open. Open **Settings** or **Quit Switchboard** from its menu-bar icon. While Chrome, Helium, or another supported Chromium browser is focused, press **Control–Option–Space** to open the destination picker. Choose a browser/profile to open the same URL there and bring that browser forward. The original tab stays open; the destination uses its own login/session. Manual selections override routing rules for that opening only.

The initial favorites are **Helium · Ryan** and **Chrome · Horizon 3** (Chrome’s `horizon3.ai` profile), when those names resolve unambiguously. They are saved as browser paths and profile directory identifiers. Favorites appear first and have **Command–1**, **Command–2**, etc. shortcuts. Use the stars to add or remove favorites.

In **Settings → Quick Switch**, check the destinations you want in the picker. **Favorites Only** selects your saved favorites; **Show All** includes every discovered browser/profile again. Once you customize the selection, newly discovered profiles stay unchecked. Selection and favorites are separate: a hidden favorite stays saved but gets no picker shortcut until you show it again. Missing selected destinations remain visible with a recovery message; they never silently select another profile. The picker shows browser icons and profile names, with the link above the destination list.

macOS asks for Automation access the first time Switchboard reads each browser’s current tab. If access is denied, the picker offers Automation Settings and a URL field for pasting the link instead. Only HTTP/HTTPS links are accepted. Reading the URL does not require enabling JavaScript from Apple Events.

The shortcut captures the focused browser’s process before opening the picker and sends the URL request to that exact process. Separate automation browsers can share Chrome’s bundle identifier; they are not interchangeable with your focused browser. If the captured process closes, the picker reports the failure rather than reading another instance.

Automation lists the controlling app, so expand **Switchboard** to enable its browser targets. macOS creates that entry when Switchboard requests access; Automation has no manual Add button. If the entry is missing, reopen the installed app, focus the browser, and invoke the shortcut again.

Click the shortcut button in Switchboard’s settings to record a different shortcut; Escape cancels. Registration conflicts appear there, and the previous registered shortcut remains available until a replacement succeeds. The menu-bar icon also offers **Open Current Page**, **Settings**, and **Quit**. Closing the settings window leaves the shortcut available. Quit Switchboard to stop it.

Enable **Launch Switchboard at login** in Settings to start the menu bar and shortcut automatically when you sign in, with Settings closed. This uses macOS’s login-item registration and reflects changes made in **System Settings → General → Login Items**. If macOS requires approval, Settings shows a button to open Login Items. Registration is optional and is changed only through the toggle, not by building, installing, or opening links.

Shortcut, favorite, and destination preferences live in the optional `picker` section of `config.json`; existing configuration files continue to load. An omitted `picker.destinations` preserves the previous behavior of showing all destinations. A saved array contains explicit browser/profile pairs; an empty array hides all destinations until you select some in Settings. Routing rules and the default destination are unaffected. Link-only launches keep their temporary lifecycle. To use the shortcut after quitting, reopen Switchboard normally.

## Development

```sh
make test     # Fast isolated regression tests; no app or real browser is launched
make verify   # Formatting, tests, Debug/Release builds, bundle and whitespace checks
make format   # Apply Swift formatting
make debug    # Build Debug into .build/xcode
make release  # Build Release into .build/xcode
```

Tests use Swift Testing through `Package.swift`, compiling the same production source files without the app entry point or editor view. Use `make test` rather than `xcodebuild test`. There are no third-party package dependencies. Swift 6 concurrency checks and Swift warnings-as-errors are enabled for the app.

Normal verification does not install the app or modify your configuration. Xcode automatically registers build products; the build commands unregister their local products afterward. Explicit installation registers the copy in `/Applications`.

Debug and Release builds are signed locally with their Automation entitlement and hardened runtime. Bundle checks verify the actual signatures and embedded entitlements on every architecture. The default is an ad-hoc signature, which may require granting privacy permissions again after a rebuild. To use a stable signing certificate already available on your Mac, pass `SIGNING_IDENTITY="Your Code Signing Identity"` to the build or install command.

Installation stages and verifies the new app before atomically replacing the installed bundle. Old Debug libraries are removed with the previous bundle instead of being merged into a Release installation, and an invalid replacement leaves the installed app untouched.

GitHub Actions runs `make verify` for pull requests and pushes to `main`, using the Xcode 26.4 family on `macos-26`. Failure logs are uploaded as artifacts. The workflow starts running once it is pushed to GitHub.

For changes to URL handling or launching, also smoke-check the app on macOS: open links with the browser closed and already running, confirm the selected profile, open several links quickly, and verify an open editor stays open. Automated fixtures cannot establish actual browser-window delivery or compatibility with every supported macOS release.
