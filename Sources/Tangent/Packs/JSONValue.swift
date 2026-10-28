import Foundation

/// Minimal JSON tree. Pack files are loosely-typed and heterogeneous
/// (a control file mixes number/string/bool/null values), so decoding into
/// strongly-typed Codable structs fights the format. This keeps the raw shape
/// and lets each parser validate what it actually needs.
enum JSONValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init?(any value: Any) {
        switch value {
        case let value as NSNull:
            _ = value
            self = .null
        case let value as NSNumber:
            // NSNumber also covers booleans; CFBoolean identity disambiguates.
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as String:
            self = .string(value)
        case let value as [String: Any]:
            var object: [String: JSONValue] = [:]
            for (key, element) in value {
                guard let parsed = JSONValue(any: element) else { return nil }
                object[key] = parsed
            }
            self = .object(object)
        case let value as [Any]:
            var array: [JSONValue] = []
            for element in value {
                guard let parsed = JSONValue(any: element) else { return nil }
                array.append(parsed)
            }
            self = .array(array)
        default:
            return nil
        }
    }

    static func load(from url: URL) throws -> JSONValue {
        let data = try Data(contentsOf: url)
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let value = JSONValue(any: any) else {
            throw PackFormatError.unsupportedJSON(url.lastPathComponent)
        }
        return value
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case let .number(value) = self { return Int(value) }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    /// Case-insensitive lookup: the format uses PascalCase, but packs in the
    /// wild vary and a silent miss would drop metadata.
    func value(forKey key: String) -> JSONValue? {
        guard let object = objectValue else { return nil }
        if let exact = object[key] { return exact }
        let lowered = key.lowercased()
        for (candidate, value) in object where candidate.lowercased() == lowered {
            return value
        }
        return nil
    }

    /// JavaScript literal for injection into a WKWebView.
    var jsLiteral: String {
        switch self {
        case .string(let value):
            return Self.quote(value)
        case .number(let value):
            if value == value.rounded(), abs(value) < 1e15 {
                return String(Int64(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        case .array(let values):
            return "[" + values.map(\.jsLiteral).joined(separator: ",") + "]"
        case .object(let values):
            let pairs = values.keys.sorted().map { "\(Self.quote($0)):\(values[$0]!.jsLiteral)" }
            return "{" + pairs.joined(separator: ",") + "}"
        }
    }

    /// Plain Foundation object for `JSONSerialization`.
    var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        case .array(let values): return values.map(\.anyValue)
        case .object(let values): return values.mapValues(\.anyValue)
        }
    }

    /// Re-encodes the tree. Used when writing a customised copy of a pack's
    /// control file.
    func serialized(pretty: Bool = true) -> Data? {
        let options: JSONSerialization.WritingOptions = pretty
            ? [.prettyPrinted, .sortedKeys]
            : []
        return try? JSONSerialization.data(withJSONObject: anyValue, options: options)
    }

    static func quote(_ value: String) -> String {
        var out = "\""
        for character in value.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{2028}": out += "\\u2028"
            case "\u{2029}": out += "\\u2029"
            default:
                if character.value < 0x20 {
                    out += String(format: "\\u%04x", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        return out + "\""
    }
}

enum PackFormatError: LocalizedError {
    case unsupportedJSON(String)
    case invalidControl(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedJSON(let name):
            return "\(name) is not a JSON object or array."
        case .invalidControl(let name):
            return "\(PackFormat.propertiesFile) control '\(name)' is malformed."
        }
    }
}
