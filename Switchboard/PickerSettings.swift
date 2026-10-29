import AppKit
import Carbon.HIToolbox

extension KeyboardShortcut {
    var isValid: Bool {
        let allowed = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        return keyCode <= 127 && modifiers & ~allowed == 0
            && modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 && !key.isEmpty
    }

    var label: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + key
    }

    static func recording(_ event: NSEvent) -> KeyboardShortcut? {
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let key: String
        switch Int(event.keyCode) {
        case kVK_Space: key = "Space"
        case kVK_Return: key = "Return"
        case kVK_Tab: key = "Tab"
        case kVK_LeftArrow: key = "←"
        case kVK_RightArrow: key = "→"
        case kVK_UpArrow: key = "↑"
        case kVK_DownArrow: key = "↓"
        default: key = event.charactersIgnoringModifiers?.uppercased() ?? ""
        }
        let shortcut = KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
        return shortcut.isValid ? shortcut : nil
    }
}

extension PickerSettings {
    // Resolve display names once. All later opens use the saved browser + directory identity.
    static func initial(browsers: [InstalledBrowser], profileStore: BrowserProfiles) -> PickerSettings {
        let requested = [
            ("net.imput.helium", "Ryan", "Ryan"),
            ("com.google.Chrome", "horizon3.ai", "Horizon 3"),
        ]
        var settings = PickerSettings()
        for (bundleID, profileName, label) in requested {
            guard let browser = browsers.first(where: { Bundle(url: $0.url)?.bundleIdentifier == bundleID }),
                let profiles = try? profileStore.profiles(browserPath: browser.path)
            else { continue }
            let matches = profiles.filter { $0.name == profileName }
            guard matches.count == 1 else { continue }
            settings.favorites.append(
                PickerFavorite(browser: browser.path, profile: matches[0].directory, name: label))
        }
        return settings
    }
}

struct PickerChoice: Identifiable {
    let destination: Destination
    let browserName: String
    let profileName: String
    let isFavorite: Bool
    var error: String? = nil

    var id: Destination { destination }
    var browserDisplayName: String {
        browserName.hasSuffix(".app") ? String(browserName.dropLast(4)) : browserName
    }
    var label: String { "\(browserDisplayName) · \(profileName)" }
}

struct PickerCatalog {
    var profileStore = BrowserProfiles()

    func choices(
        browsers: [InstalledBrowser], favorites: [PickerFavorite], destinations: [Destination] = []
    ) -> [PickerChoice] {
        var choices: [PickerChoice] = []
        var errors: [String: String] = [:]
        for browser in browsers.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        {
            do {
                for profile in try profileStore.profiles(browserPath: browser.path) {
                    choices.append(
                        PickerChoice(
                            destination: Destination(browser: browser.path, profile: profile.directory),
                            browserName: browser.name, profileName: profile.name, isFavorite: false))
                }
            } catch {
                errors[browser.path] = error.localizedDescription
            }
        }
        var pinned: [PickerChoice] = []
        for favorite in favorites where !pinned.contains(where: { $0.id == favorite.id }) {
            let existing = choices.first { $0.id == favorite.id }
            let browserName =
                browsers.first { $0.path == favorite.browser }?.name
                ?? ((favorite.browser as NSString).lastPathComponent as NSString).deletingPathExtension
            pinned.append(
                PickerChoice(
                    destination: favorite.destination, browserName: browserName, profileName: favorite.name,
                    isFavorite: true,
                    error: existing == nil
                        ? (errors[favorite.browser]
                            ?? "This browser or profile is unavailable. Refresh or deselect it in Quick Switch settings.")
                        : nil))
        }
        choices.removeAll { choice in pinned.contains { $0.id == choice.id } }
        // A selected destination must remain identifiable if discovery fails or it disappears.
        // Never substitute a matching directory or display name from another browser.
        for destination in destinations
        where !pinned.contains(where: { $0.id == destination })
            && !choices.contains(where: { $0.id == destination })
        {
            choices.append(
                PickerChoice(
                    destination: destination,
                    browserName: ((destination.browser as NSString).lastPathComponent as NSString)
                        .deletingPathExtension,
                    profileName: destination.profile, isFavorite: false,
                    error: errors[destination.browser]
                        ?? "This browser or profile is unavailable. Refresh or deselect it in Quick Switch settings."
                ))
        }
        // Keep discovery failures visible even for browsers that have no favorites.
        for browser in browsers
        where errors[browser.path] != nil
            && !pinned.contains(where: { $0.destination.browser == browser.path })
            && !choices.contains(where: { $0.destination.browser == browser.path })
        {
            choices.append(
                PickerChoice(
                    destination: Destination(browser: browser.path, profile: ""), browserName: browser.name,
                    profileName: "Profiles unavailable", isFavorite: false, error: errors[browser.path]))
        }
        return pinned + choices
    }
}
