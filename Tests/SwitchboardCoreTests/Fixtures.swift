import Foundation

struct Fixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("switchboard-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    var configURL: URL { root.appendingPathComponent("config.json") }
    var historyURL: URL { root.appendingPathComponent("state/switchboard/history.jsonl") }

    func browser(
        id: String = "com.google.Chrome", executable: String = "ActualBrowser",
        name: String = "RenamedBrowser", bundleName: String? = nil
    ) throws -> URL {
        let app = root.appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        var info = [
            "CFBundleIdentifier": id, "CFBundleExecutable": executable, "CFBundlePackageType": "APPL",
        ]
        info["CFBundleName"] = bundleName
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try FileManager.default.createSymbolicLink(
            at: contents.appendingPathComponent("MacOS/\(executable)"),
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/true")
        )
        return app
    }

    func profiles(_ profiles: [String: String], folder: String = "Google/Chrome") throws {
        let state = root.appendingPathComponent("Library/Application Support/\(folder)/Local State")
        try FileManager.default.createDirectory(
            at: state.deletingLastPathComponent(), withIntermediateDirectories: true)
        let cache = profiles.mapValues { ["name": $0] }
        try JSONSerialization.data(withJSONObject: ["profile": ["info_cache": cache]]).write(to: state)
    }
}
