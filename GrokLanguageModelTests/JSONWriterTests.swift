//
//  JSONWriterTests.swift
//  GrokLanguageModelTests
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels
import Testing
@testable import GrokLanguageModel

/// Tests for the ordered JSON writer that request bodies use.
struct JSONWriterTests {
    @Test func escapesStrings() throws {
        let text = try written(.string("a\"b\\c/d\u{0}\u{1F}\n\t\r\u{8}\u{C}\u{7F}é😀"))

        #expect(text == #""a\"b\\c/d\u0000\u001f\n\t\r\b\f"# + "\u{7F}é😀\"")
    }

    @Test func escapesStringsLikeJSONEncoder() throws {
        // Every ASCII character, plus characters that take several UTF-8 bytes.
        let string = String((0..<128).map { Character(Unicode.Scalar(UInt8($0))) }) + "é€😀\u{2028}"

        let text = try written(.string(string))

        // JSONEncoder also escapes forward slashes, which JSON doesn't require.
        let encoded = String(decoding: try JSONEncoder().encode(string), as: UTF8.self)
        #expect(text == encoded.replacingOccurrences(of: #"\/"#, with: "/"))
        #expect(try JSONDecoder().decode(String.self, from: Data(text.utf8)) == string)
    }

    @Test func writesScalarsLikeJSONEncoder() throws {
        for number in [0.4, 0.1 + 0.2, -2.5, 1e21, 1e-7, 123_456_789.125, 1.7976931348623157e308, 5e-324] {
            #expect(try written(.number(number)) == String(decoding: try JSONEncoder().encode(number), as: UTF8.self))
        }
        for integer in [0, -1, 42, Int.max, Int.min] {
            #expect(try written(.integer(integer)) == String(decoding: try JSONEncoder().encode(integer), as: UTF8.self))
        }
        #expect(try written(.bool(true)) == "true")
        #expect(try written(.bool(false)) == "false")
        #expect(try written(.null) == "null")
        #expect(try written(.array([])) == "[]")
        #expect(try written(.object([:])) == "{}")
    }

    @Test func throwsForNumbersThatJSONCannotRepresent() {
        #expect(throws: EncodingError.self) {
            try JSONValue.number(.infinity).jsonData()
        }
    }

    @Test func roundTripsThroughJSONDecoder() throws {
        let value = JSONValue.object([
            "string": .string("Line one\nLine \"two\" \\ \u{1} café 🌸"),
            "integer": .integer(-42),
            "number": .number(3.25),
            "bool": .bool(true),
            "null": .null,
            "array": .array([.integer(1), .string("two"), .array([]), .object([:]), .null]),
            "nested": .object(["b": .bool(false), "a": .array([.number(0.5)])]),
            "": .string("empty key"),
            "key with \"quotes\" and\nnewline": .string("value"),
        ])

        let data = try value.jsonData()

        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
    }

    @Test func sortsTheKeysOfOtherObjects() throws {
        let value = JSONValue.object([
            "b": .integer(1),
            "a": .object(["z": .null, "y": .bool(true)]),
            "c": .array([.object(["k2": .integer(2), "k1": .integer(1)])]),
            "B": .string("uppercase"),
        ])

        #expect(try written(value) == #"{"B":"uppercase","a":{"y":true,"z":null},"b":1,"c":[{"k1":1,"k2":2}]}"#)
    }

    @Test func ordersSchemaPropertiesByXOrder() throws {
        let schema = JSONValue.object([
            "type": .string("object"),
            "properties": .object([
                "zulu": .object(["type": .string("string")]),
                "mike": .object(["$ref": .string("#/$defs/Detail")]),
                "alpha": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object(["b": .object([:]), "a": .object([:])]),
                        "x-order": .array([.string("b"), .string("a")]),
                    ]),
                ]),
                // Properties that x-order doesn't list follow in sorted order.
                "extra2": .object([:]),
                "extra1": .object([:]),
            ]),
            // Duplicates and names without a property are skipped.
            "x-order": .array([.string("zulu"), .string("mike"), .string("zulu"), .string("missing"), .string("alpha")]),
            "$defs": .object([
                "Detail": .object([
                    "type": .string("object"),
                    "properties": .object(["yankee": .object([:]), "bravo": .object([:])]),
                    "x-order": .array([.string("yankee"), .string("bravo")]),
                ]),
            ]),
        ])

        let text = try written(schema)

        #expect(text == ##"{"$defs":{"Detail":{"properties":{"yankee":{},"bravo":{}},"type":"object","x-order":["yankee","bravo"]}},"properties":{"zulu":{"type":"string"},"mike":{"$ref":"#/$defs/Detail"},"alpha":{"items":{"properties":{"b":{},"a":{}},"type":"object","x-order":["b","a"]},"type":"array"},"extra1":{},"extra2":{}},"type":"object","x-order":["zulu","mike","zulu","missing","alpha"]}"##)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) == schema)
    }

    @Test func sortsPropertiesWithoutAListOfNames() throws {
        let properties = JSONValue.object(["b": .object([:]), "a": .object([:])])

        let string = try written(.object(["properties": properties, "x-order": .string("b")]))
        let mixed = try written(.object(["properties": properties, "x-order": .array([.string("b"), .integer(1)])]))

        #expect(string == #"{"properties":{"a":{},"b":{}},"x-order":"b"}"#)
        #expect(mixed == #"{"properties":{"a":{},"b":{}},"x-order":["b",1]}"#)
    }

    @Test func writesTheObjectsOwnSpellingOfPropertyNames() throws {
        // Swift treats these strings as equal, although their bytes differ.
        let composed = "caf\u{E9}"
        let decomposed = "cafe\u{301}"
        let schema = JSONValue.object([
            "properties": .object([composed: .object([:]), "b": .object([:])]),
            "x-order": .array([.string("b"), .string(decomposed)]),
        ])

        // Compare bytes, because comparing strings ignores the difference.
        let expected = #"{"properties":{"b":{},""# + composed + #"":{}},"x-order":["b",""# + decomposed + #""]}"#
        #expect(try schema.jsonData() == Data(expected.utf8))
    }

    @Test func writesTheSameTextEveryTime() throws {
        // Encoding a schema to a dictionary gives its keys a different order
        // each time, so this checks that the writer doesn't depend on it.
        let texts = try (0..<50).map { _ in
            try written(JSONValue(encoding: OrderedReport.generationSchema))
        }

        #expect(Set(texts).count == 1)
    }

    @Test func writesGenerableSchemasInDeclarationOrder() throws {
        let text = try written(JSONValue(encoding: OrderedReport.generationSchema))

        expectKeys(["zuluHeadline", "mikeCount", "alphaFlag", "detail", "bravoTags"], inOrderIn: text)
        expectKeys(["yankeeNote", "charlieScore"], inOrderIn: text)
    }

    // MARK: Requests

    @Test func sendsSchemaPropertiesInDeclarationOrder() throws {
        let request = LanguageModelExecutorGenerationRequest(
            id: UUID(),
            transcript: Transcript(entries: [.prompt(.init(segments: [.text(.init(content: "Report"))]))]),
            enabledTools: [Transcript.ToolDefinition(tool: OrderedSearchTool())],
            schema: OrderedReport.generationSchema,
            generationOptions: GenerationOptions(temperature: 0.7),
            contextOptions: ContextOptions(),
            metadata: [:]
        )
        let body = try ResponsesRequest(request: request, model: .grok4_3)

        let urlRequest = try GrokConfiguration(apiKey: "key").makeURLRequest(body: body, environment: [:])

        // Inspect the raw bytes, because decoding them loses the key order.
        let data = try #require(urlRequest.httpBody)
        let text = String(decoding: data, as: UTF8.self)
        expectKeys(["zuluHeadline", "mikeCount", "alphaFlag", "detail", "bravoTags"], inOrderIn: text)
        expectKeys(["yankeeNote", "charlieScore"], inOrderIn: text)
        expectKeys(["xrayQuery", "limitCount", "categoryName"], inOrderIn: text)
        // The body has the same keys and values that JSONEncoder writes.
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == JSONValue(encoding: body))
    }

    @Test func sessionsSendSchemaPropertiesInDeclarationOrder() async throws {
        let json = #"{"zuluHeadline":"News","mikeCount":3,"alphaFlag":true,"detail":{"yankeeNote":"Fine","charlieScore":0.5},"bravoTags":["a"]}"#
        let server = MockServer(replies: [.events(Events.textResponse(json))])
        let session = LanguageModelSession(model: server.model(), tools: [OrderedSearchTool()])

        let response = try await session.respond(to: "Report", generating: OrderedReport.self)

        #expect(response.content.zuluHeadline == "News")
        #expect(response.content.detail.charlieScore == 0.5)
        let body = String(decoding: try #require(server.bodies.first), as: UTF8.self)
        expectKeys(["zuluHeadline", "mikeCount", "alphaFlag", "detail", "bravoTags"], inOrderIn: body)
        expectKeys(["yankeeNote", "charlieScore"], inOrderIn: body)
        expectKeys(["xrayQuery", "limitCount", "categoryName"], inOrderIn: body)
    }

    // MARK: Helpers

    private func written(_ value: JSONValue) throws -> String {
        String(decoding: try value.jsonData(), as: UTF8.self)
    }

    /// Expects each key to appear as an object key in the JSON text, in order.
    private func expectKeys(_ keys: [String], inOrderIn text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let positions = keys.compactMap { text.range(of: "\"\($0)\":")?.lowerBound }
        #expect(positions.count == keys.count, "Some of \(keys) are missing from \(text)", sourceLocation: sourceLocation)
        #expect(positions == positions.sorted(), "\(keys) aren't in declaration order in \(text)", sourceLocation: sourceLocation)
    }
}

// The properties of these types are declared out of alphabetical order.

@Generable
struct OrderedReport {
    @Guide(description: "A short headline")
    var zuluHeadline: String
    var mikeCount: Int
    var alphaFlag: Bool
    var detail: OrderedDetail
    var bravoTags: [String]
}

@Generable
struct OrderedDetail {
    var yankeeNote: String
    var charlieScore: Double
}

struct OrderedSearchTool: Tool {
    let name = "search"
    let description = "Searches a catalog."

    @Generable
    struct Arguments {
        var xrayQuery: String
        var limitCount: Int
        var categoryName: String
    }

    @concurrent func call(arguments: Arguments) async throws -> String {
        "No results."
    }
}
