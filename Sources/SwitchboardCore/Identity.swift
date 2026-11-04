// The names Switchboard goes by: the app, its bundle identifier, the command-line tool, its
// folders and environment variables. They are the previous Swift app's, so this app replaces it
// in place: macOS keeps it as the default browser and login item, and it reads the same settings.
public enum Identity {
    /// The app's display name.
    public static let appName = "Switchboard"
    /// The macOS bundle identifier.
    public static let bundleID = "com.switchboard.app"
    /// The command-line tool's name, as people type it.
    public static let cliName = "switchboard"
    /// The SwiftPM product that builds the command-line tool. It isn't `switchboard`, because macOS
    /// file systems ignore case and the app's executable, `Switchboard`, is built beside it;
    /// scripts/bundle installs it under `cliName`.
    public static let cliProduct = "switchboard-cli"
    /// The folder name under `~/.config` and `~/.local/state`.
    public static let directoryName = "switchboard"
    /// The prefix of the environment variables Switchboard reads, such as `SWITCHBOARD_CONFIG`.
    public static let environmentPrefix = "SWITCHBOARD"
}
