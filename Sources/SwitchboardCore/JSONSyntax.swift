// Where a JSON document first goes wrong, as "line L, column C". Foundation's decoders don't say
// on every platform, and a position is what lets a person or an agent fix a hand edit. Used only
// after decoding has already failed, so it favours simplicity over speed.

enum JSONSyntax {
    struct Failure: Error, Equatable {
        var line: Int
        var column: Int
        var reason: String

        var description: String { "\(reason) at line \(line), column \(column)." }
    }

    /// The first syntax error in `bytes`, or `nil` when the document is well formed.
    static func firstError(in bytes: [UInt8]) -> Failure? {
        var parser = Parser(bytes: bytes)
        do throws(Failure) {
            parser.skipSpace()
            try parser.value(depth: 0)
            parser.skipSpace()
            if parser.index < bytes.count { throw parser.fail("Unexpected text after the document") }
            return nil
        } catch {
            return error
        }
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        func fail(_ reason: String) -> Failure {
            var line = 1
            var column = 1
            for byte in bytes[..<min(index, bytes.count)] {
                if byte == UInt8(ascii: "\n") {
                    line += 1
                    column = 1
                } else if byte & 0xC0 != 0x80 {
                    column += 1
                }
            }
            return Failure(line: line, column: column, reason: reason)
        }

        var current: UInt8? { index < bytes.count ? bytes[index] : nil }

        mutating func skipSpace() {
            while let c = current, c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 { index += 1 }
        }

        mutating func expect(_ text: String) throws(Failure) {
            for byte in text.utf8 {
                guard current == byte else { throw fail("Expected “\(text)”") }
                index += 1
            }
        }

        mutating func value(depth: Int) throws(Failure) {
            guard depth < 512 else { throw fail("Nested too deeply") }
            guard let c = current else { throw fail("The document ends where a value was expected") }
            switch c {
            case UInt8(ascii: "{"): try object(depth: depth)
            case UInt8(ascii: "["): try array(depth: depth)
            case UInt8(ascii: "\""): try string()
            case UInt8(ascii: "t"): try expect("true")
            case UInt8(ascii: "f"): try expect("false")
            case UInt8(ascii: "n"): try expect("null")
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): try number()
            default: throw fail("Unexpected character where a value was expected")
            }
        }

        mutating func object(depth: Int) throws(Failure) {
            index += 1
            skipSpace()
            if current == UInt8(ascii: "}") {
                index += 1
                return
            }
            while true {
                skipSpace()
                guard current == UInt8(ascii: "\"") else {
                    throw fail(
                        current == nil ? "The document ends inside an object" : "Expected a quoted key")
                }
                try string()
                skipSpace()
                guard current == UInt8(ascii: ":") else { throw fail("Expected “:” after the key") }
                index += 1
                skipSpace()
                try value(depth: depth + 1)
                skipSpace()
                switch current {
                case UInt8(ascii: ","): index += 1
                case UInt8(ascii: "}"):
                    index += 1
                    return
                case nil: throw fail("The document ends inside an object")
                default: throw fail("Expected “,” or “}”")
                }
            }
        }

        mutating func array(depth: Int) throws(Failure) {
            index += 1
            skipSpace()
            if current == UInt8(ascii: "]") {
                index += 1
                return
            }
            while true {
                skipSpace()
                try value(depth: depth + 1)
                skipSpace()
                switch current {
                case UInt8(ascii: ","): index += 1
                case UInt8(ascii: "]"):
                    index += 1
                    return
                case nil: throw fail("The document ends inside a list")
                default: throw fail("Expected “,” or “]”")
                }
            }
        }

        mutating func string() throws(Failure) {
            index += 1
            while let c = current {
                switch c {
                case UInt8(ascii: "\""):
                    index += 1
                    return
                case UInt8(ascii: "\\"):
                    index += 2
                case 0..<0x20:
                    throw fail("Control character inside a string")
                default:
                    index += 1
                }
            }
            throw fail("The document ends inside a string")
        }

        mutating func number() throws(Failure) {
            let digits = UInt8(ascii: "0")...UInt8(ascii: "9")
            if current == UInt8(ascii: "-") { index += 1 }
            guard let first = current, digits.contains(first) else { throw fail("Expected a digit") }
            while let c = current, digits.contains(c) || "+-.eE".utf8.contains(c) { index += 1 }
        }
    }
}
