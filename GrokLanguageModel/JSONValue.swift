//
//  JSONValue.swift
//  GrokLanguageModel
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation

/// An arbitrary JSON value, used for JSON schemas and error bodies.
enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue {
    /// Creates a JSON value from the JSON encoding of a value.
    init(encoding value: some Encodable) throws {
        let data = try JSONEncoder().encode(value)
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    subscript(index: Int) -> JSONValue? {
        guard case .array(let array) = self, array.indices.contains(index) else { return nil }
        return array[index]
    }

    var stringValue: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    /// The value as text if it's a string, number, or Boolean.
    var textValue: String? {
        switch self {
        case .string(let string): string
        case .integer(let integer): String(integer)
        case .number(let number): String(number)
        case .bool(let bool): String(bool)
        case .null, .array, .object: nil
        }
    }
}

// MARK: - Writing

extension JSONValue {
    /// The compact JSON text of the value, with object keys in a deterministic
    /// order.
    ///
    /// `JSONEncoder` writes the keys of a dictionary in an unspecified order,
    /// which changes from run to run. The xAI API generates the properties of
    /// a JSON schema object in the order that its `properties` keys appear, so
    /// this writes those keys in the order that the schema's `x-order` keyword
    /// lists them, which is the order that a `@Generable` type declares its
    /// properties. Keys that `x-order` doesn't list follow in sorted order, and
    /// the keys of every other object are sorted.
    ///
    /// Strings and numbers are written the same way that `JSONEncoder` writes
    /// them, except that forward slashes aren't escaped.
    func jsonData() throws -> Data {
        var writer = JSONWriter()
        try writer.write(self)
        return Data(writer.bytes)
    }
}

/// Writes compact JSON text for a `JSONValue`.
private struct JSONWriter {
    private(set) var bytes: [UInt8] = []
    private let numberEncoder = JSONEncoder()

    mutating func write(_ value: JSONValue) throws {
        switch value {
        case .null:
            append("null")
        case .bool(let bool):
            append(bool ? "true" : "false")
        case .integer(let integer):
            append(String(integer))
        case .number(let number):
            // Throws for values that JSON can't represent, like infinity.
            bytes.append(contentsOf: try numberEncoder.encode(number))
        case .string(let string):
            write(string)
        case .array(let array):
            bytes.append(UInt8(ascii: "["))
            for (index, element) in array.enumerated() {
                if index > 0 { bytes.append(UInt8(ascii: ",")) }
                try write(element)
            }
            bytes.append(UInt8(ascii: "]"))
        case .object(let object):
            try write(object, keyOrder: nil)
        }
    }

    /// Writes an object's keys in `keyOrder`, then the remaining keys in
    /// sorted order.
    ///
    /// An object with a `keyOrder` is a schema's `properties`, whose keys are
    /// property names rather than schema keywords.
    private mutating func write(_ object: [String: JSONValue], keyOrder: [String]?) throws {
        bytes.append(UInt8(ascii: "{"))
        for (index, key) in Self.orderedKeys(of: object, keyOrder: keyOrder).enumerated() {
            if index > 0 { bytes.append(UInt8(ascii: ",")) }
            write(key)
            bytes.append(UInt8(ascii: ":"))
            let value = object[key]!
            if keyOrder == nil, key == "properties", case .object(let properties) = value,
               let order = Self.propertyOrder(ofSchema: object) {
                try write(properties, keyOrder: order)
            } else {
                try write(value)
            }
        }
        bytes.append(UInt8(ascii: "}"))
    }

    /// The property names that a JSON schema object lists in `x-order`, or
    /// `nil` if it doesn't list them.
    private static func propertyOrder(ofSchema schema: [String: JSONValue]) -> [String]? {
        guard case .array(let elements) = schema["x-order"] else { return nil }
        let names = elements.compactMap(\.stringValue)
        return names.count == elements.count ? names : nil
    }

    private static func orderedKeys(of object: [String: JSONValue], keyOrder: [String]?) -> [String] {
        guard let keyOrder else { return object.keys.sorted() }
        var written = Set<String>()
        // Strings that are canonically equivalent are equal even when their
        // Unicode scalars differ, so write the object's own spelling of each
        // key rather than the spelling in `keyOrder`.
        let ordered = keyOrder
            .compactMap { name in object.index(forKey: name).map { object[$0].key } }
            .filter { written.insert($0).inserted }
        return ordered + object.keys.filter { !written.contains($0) }.sorted()
    }

    private mutating func write(_ string: String) {
        bytes.append(UInt8(ascii: "\""))
        let utf8 = string.utf8
        var runStart = utf8.startIndex
        for index in utf8.indices {
            let byte = utf8[index]
            let escape: String
            switch byte {
            case UInt8(ascii: "\""): escape = "\\\""
            case UInt8(ascii: "\\"): escape = "\\\\"
            case 0x08: escape = "\\b"
            case 0x09: escape = "\\t"
            case 0x0A: escape = "\\n"
            case 0x0C: escape = "\\f"
            case 0x0D: escape = "\\r"
            case 0x00..<0x20:
                let hex = String(byte, radix: 16, uppercase: false)
                escape = "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default:
                // ASCII and the bytes of multibyte UTF-8 sequences are written as they are.
                continue
            }
            bytes.append(contentsOf: utf8[runStart..<index])
            append(escape)
            runStart = utf8.index(after: index)
        }
        bytes.append(contentsOf: utf8[runStart...])
        bytes.append(UInt8(ascii: "\""))
    }

    private mutating func append(_ text: String) {
        bytes.append(contentsOf: text.utf8)
    }
}

// MARK: - Coding

extension JSONValue: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let integer = try? container.decode(Int.self) {
            self = .integer(integer)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let bool): try container.encode(bool)
        case .integer(let integer): try container.encode(integer)
        case .number(let number): try container.encode(number)
        case .string(let string): try container.encode(string)
        case .array(let array): try container.encode(array)
        case .object(let object): try container.encode(object)
        }
    }
}
