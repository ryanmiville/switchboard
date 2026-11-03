// Just enough URL parsing for routing. A link is kept as the exact string it arrived as: matching
// runs on it and launching passes it on unchanged. Only the scheme and host are read out of it.
//
// Foundation's URL is not used for links: it re-encodes characters, so the string a browser
// received could differ from the one Switchboard was given. Parsing runs on UTF-8 bytes, because
// every delimiter is ASCII and String's Character indexing would merge a delimiter with a
// combining mark that follows it.

/// The parts of a link routing needs.
public struct Link: Equatable, Sendable {
    public var scheme: String
    /// The host as written, without brackets for IPv6 and without user info or port. `nil` when
    /// the link has no `//` authority; empty when the authority is empty (`file:///tmp`).
    public var host: String?
    /// Everything after the authority, up to the query or fragment.
    public var path: String

    /// Parses `text` as an absolute URL, or returns `nil` when it isn't one: no scheme, whitespace
    /// or control characters, or a port that isn't a number.
    public init?(_ text: String) {
        guard !text.isEmpty,
            !text.unicodeScalars.contains(where: {
                $0.properties.isWhitespace || $0.properties.generalCategory == .control
            })
        else { return nil }
        let b = Array(text.utf8)
        func string(_ range: Range<Int>) -> String { String(decoding: b[range], as: UTF8.self) }
        func first(of set: [Character], in range: Range<Int>) -> Int? {
            let bytes = set.map { UInt8(ascii: $0.unicodeScalars.first!) }
            return range.first { bytes.contains(b[$0]) }
        }
        func isDigits(_ range: Range<Int>) -> Bool { range.allSatisfy { b[$0] >= 48 && b[$0] <= 57 } }

        guard let colon = first(of: [":"], in: 0..<b.count) else { return nil }
        let isAlpha = { (c: UInt8) in (65...90).contains(c) || (97...122).contains(c) }
        guard colon > 0, isAlpha(b[0]),
            (1..<colon).allSatisfy({ c in
                isAlpha(b[c]) || (48...57).contains(b[c]) || "+-.".utf8.contains(b[c])
            })
        else { return nil }
        scheme = string(0..<colon)

        let rest = (colon + 1)..<b.count
        func untilQuery(_ range: Range<Int>) -> String {
            string(range.lowerBound..<(first(of: ["?", "#"], in: range) ?? range.upperBound))
        }
        guard rest.count >= 2, b[rest.lowerBound] == UInt8(ascii: "/"),
            b[rest.lowerBound + 1] == UInt8(ascii: "/")
        else {
            host = nil
            path = untilQuery(rest)
            return
        }
        let after = (rest.lowerBound + 2)..<b.count
        let authorityEnd = first(of: ["/", "?", "#"], in: after) ?? b.count
        let authority = after.lowerBound..<authorityEnd
        let at = authority.last { b[$0] == UInt8(ascii: "@") }
        let hostPort = (at.map { $0 + 1 } ?? authority.lowerBound)..<authority.upperBound
        if hostPort.first.map({ b[$0] == UInt8(ascii: "[") }) == true {
            let bracketed = (hostPort.lowerBound + 1)..<hostPort.upperBound
            guard let close = first(of: ["]"], in: bracketed) else { return nil }
            let port = (close + 1)..<hostPort.upperBound
            guard
                port.isEmpty
                    || (b[port.lowerBound] == UInt8(ascii: ":")
                        && isDigits((port.lowerBound + 1)..<port.upperBound))
            else { return nil }
            host = string(bracketed.lowerBound..<close)
        } else if let portColon = first(of: [":"], in: hostPort) {
            guard isDigits((portColon + 1)..<hostPort.upperBound) else { return nil }
            host = string(hostPort.lowerBound..<portColon)
        } else {
            host = string(hostPort)
        }
        path = untilQuery(authorityEnd..<b.count)
    }

    /// The lowercased host of a web link.
    public static func webHost(_ text: String) -> String? {
        guard let link = Link(text), ["http", "https"].contains(link.scheme.lowercased()),
            let host = link.host, !host.isEmpty
        else { return nil }
        return host.lowercased()
    }

    /// A complete `http` or `https` link with a host.
    public static func isWeb(_ text: String) -> Bool { webHost(text) != nil }

    /// A `file:` link to an absolute local path.
    public static func isLocalFile(_ text: String) -> Bool {
        guard let link = Link(text), link.scheme.lowercased() == "file", let host = link.host else {
            return false
        }
        return (host.isEmpty || host.lowercased() == "localhost") && link.path.hasPrefix("/")
    }
}
