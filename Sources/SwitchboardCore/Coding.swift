import Foundation

// JSON helpers shared by config.json and history.jsonl: one encoder style, and decoders that
// refuse keys they don't know, so a typo in a hand or agent edit is reported instead of ignored.

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Decoder {
    /// Throws when the object at this level has a key outside `known`.
    func refuseUnknownKeys(_ known: [String]) throws {
        let container = try self.container(keyedBy: AnyKey.self)
        if let unknown = container.allKeys.map(\.stringValue).sorted().first(where: { !known.contains($0) }) {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: codingPath + [AnyKey(unknown)],
                    debugDescription:
                        "Unknown key “\(unknown)”; expected one of \(known.map { "“\($0)”" }.joined(separator: ", "))."
                ))
        }
    }
}

enum JSON {
    /// Pretty, sorted keys, unescaped slashes, and a trailing newline: readable and diffable.
    static func pretty<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = (try? encoder.encode(value)) ?? Data()
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// One line, sorted keys, unescaped slashes, no trailing newline.
    static func line<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)) ?? Data()
    }

    /// A decoding failure of `data` in words: where it happened and what was wrong.
    static func describe(_ error: Error, in data: Data) -> String {
        if let syntax = JSONSyntax.firstError(in: [UInt8](data)) {
            return "It isn’t valid JSON. \(syntax.description)"
        }
        return describe(error)
    }

    /// A decoding failure in words: where it happened and what was wrong.
    static func describe(_ error: Error) -> String {
        func path(_ codingPath: [CodingKey]) -> String {
            codingPath.isEmpty
                ? "the top level"
                : codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        switch error as? DecodingError {
        case .keyNotFound(let key, let context):
            return "“\(key.stringValue)” is missing at \(path(context.codingPath))."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(path(context.codingPath)) has the wrong type. \(context.debugDescription)"
        case .dataCorrupted(let context):
            let underlying = (context.underlyingError as NSError?).flatMap {
                $0.userInfo[NSDebugDescriptionErrorKey] as? String
            }
            if context.codingPath.isEmpty {
                return "It isn’t valid JSON. \(underlying ?? context.debugDescription)"
            }
            return "\(path(context.codingPath)) is invalid. \(context.debugDescription)"
        default:
            return "\(error)"
        }
    }
}
