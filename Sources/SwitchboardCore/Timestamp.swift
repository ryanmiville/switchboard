import Foundation

/// UTC time as whole seconds since 1970, written as RFC 3339 (`2026-10-29T17:04:11Z`). Callers pass
/// the current time in, so tests are deterministic.
public struct Timestamp: Hashable, Comparable, Sendable {
    public var seconds: Int64

    public init(_ seconds: Int64) {
        self.seconds = seconds
    }

    public init(_ date: Date) {
        self.seconds = Int64(date.timeIntervalSince1970.rounded(.down))
    }

    public static func < (a: Timestamp, b: Timestamp) -> Bool { a.seconds < b.seconds }

    public var rfc3339: String {
        let days = floorDiv(seconds, 86_400)
        let rest = seconds - days * 86_400
        let (year, month, day) = Self.civil(fromDays: days)
        return String(
            format: "%04lld-%02lld-%02lldT%02lld:%02lld:%02lldZ", year, month, day, rest / 3600,
            rest / 60 % 60,
            rest % 60)
    }

    /// Parses `YYYY-MM-DDTHH:MM:SS`, optional fractional seconds, then `Z` or `±HH:MM`.
    public init?(rfc3339 text: String) {
        let b = Array(text.utf8)
        guard b.count >= 20, b[4] == UInt8(ascii: "-"), b[7] == UInt8(ascii: "-"),
            b[10] == UInt8(ascii: "T") || b[10] == UInt8(ascii: "t"), b[13] == UInt8(ascii: ":"),
            b[16] == UInt8(ascii: ":")
        else { return nil }
        func number(_ range: Range<Int>) -> Int64? {
            guard range.allSatisfy({ b[$0] >= 48 && b[$0] <= 57 }) else { return nil }
            return range.reduce(Int64(0)) { $0 * 10 + Int64(b[$1] - 48) }
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
            let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19)
        else { return nil }
        var index = 19
        if b[index] == UInt8(ascii: ".") {
            index += 1
            while index < b.count, b[index] >= 48, b[index] <= 57 { index += 1 }
        }
        let rest = Array(b[index...])
        let offset: Int64
        if rest == [UInt8(ascii: "Z")] || rest == [UInt8(ascii: "z")] {
            offset = 0
        } else if rest.count == 6, rest[3] == UInt8(ascii: ":"),
            rest[0] == UInt8(ascii: "+") || rest[0] == UInt8(ascii: "-"),
            let hours = Int64(String(decoding: rest[1..<3], as: UTF8.self)),
            let minutes = Int64(String(decoding: rest[4..<6], as: UTF8.self))
        {
            offset = (rest[0] == UInt8(ascii: "+") ? 1 : -1) * (hours * 3600 + minutes * 60)
        } else {
            return nil
        }
        seconds =
            Self.days(year: year, month: month, day: day) * 86_400 + hour * 3600 + minute * 60 + second
            - offset
    }

    /// "now", "45s ago", "2m ago", "3h ago", "4d ago".
    public func ago(_ now: Timestamp) -> String {
        let s = max(now.seconds - seconds, 0)
        switch s {
        case 0..<5: return "now"
        case 5..<60: return "\(s)s ago"
        case 60..<3600: return "\(s / 60)m ago"
        case 3600..<86_400: return "\(s / 3600)h ago"
        default: return "\(s / 86_400)d ago"
        }
    }

    // Howard Hinnant's civil-calendar algorithms.
    static func days(year: Int64, month: Int64, day: Int64) -> Int64 {
        let y = month <= 2 ? year - 1 : year
        let era = floorDiv(y, 400)
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civil(fromDays days: Int64) -> (Int64, Int64, Int64) {
        let z = days + 719_468
        let era = floorDiv(z, 146_097)
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }
}

private func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}
