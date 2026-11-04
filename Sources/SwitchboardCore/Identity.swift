// Names that change when Switchboard Next replaces the current app. Until then it uses its own
// name, bundle identifier and folders, so the two can run side by side without the current app's
// saves dropping fields it doesn't know. The rename at the merge is a change to this file only.
public enum Identity {
    /// The app's display name.
    public static let appName = "Switchboard Next"
    /// The macOS bundle identifier.
    public static let bundleID = "com.switchboard.next"
    /// The command-line tool's name.
    public static let cliName = "switchboard-next"
    /// The folder name under `~/.config` and `~/.local/state`.
    public static let directoryName = "switchboard-next"
    /// The prefix of the environment variables Switchboard reads, such as `SWITCHBOARD_NEXT_CONFIG`.
    public static let environmentPrefix = "SWITCHBOARD_NEXT"
}
