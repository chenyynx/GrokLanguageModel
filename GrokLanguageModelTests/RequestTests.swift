//
//  RequestTests.swift
//  GrokLanguageModelTests
//
//  Created by Marcus Arnett on 9/28/26.
//

import CoreGraphics
import CoreImage
import Foundation
import FoundationModels
import Testing
@testable import GrokLanguageModel

// Serialized, so that the tests that encode images don't create Core Image
// contexts at the same time, which can stall in a newly booted simulator.
@Suite(.serialized)
struct RequestTests {
    @Test func mapsGenerationOptions() throws {
        let body = try encodedRequest(options: GenerationOptions(temperature: 0.4, maximumResponseTokens: 500))

        #expect(body["temperature"] == .number(0.4))
        #expect(body["max_output_tokens"] == .integer(500))
        #expect(body["top_k"] == nil)
        #expect(body["top_p"] == nil)
    }

    @Test(arguments: [
        (GenerationOptions.SamplingMode.greedy, "top_k", JSONValue.integer(1)),
        (.random(top: 40), "top_k", .integer(40)),
        (.random(probabilityThreshold: 0.9), "top_p", .number(0.9)),
    ])
    func mapsSamplingModes(mode: GenerationOptions.SamplingMode, key: String, value: JSONValue) throws {
        let body = try encodedRequest(options: GenerationOptions(samplingMode: mode))

        #expect(body[key] == value)
    }

    @Test(arguments: [
        (GenerationOptions.ToolCallingMode.allowed, "auto"),
        (.required, "required"),
        (.disallowed, "none"),
    ])
    func mapsToolCallingModes(mode: GenerationOptions.ToolCallingMode, choice: String) throws {
        let body = try encodedRequest(
            tools: [Transcript.ToolDefinition(tool: WeatherTool())],
            options: GenerationOptions(toolCallingMode: mode)
        )

        #expect(body["tool_choice"] == .string(choice))
    }

    @Test func omitsToolChoiceWithoutTools() throws {
        let body = try encodedRequest(options: GenerationOptions(toolCallingMode: .required))

        #expect(body["tools"] == nil)
        #expect(body["tool_choice"] == nil)
    }

    @Test func prefersTheRequestReasoningLevel() throws {
        let model = GrokModel.grok4_7.reasoningEffort(.low)

        let defaultBody = try encodedRequest(model: model)
        let deepBody = try encodedRequest(model: model, contextOptions: ContextOptions(reasoningLevel: .deep))
        let customBody = try encodedRequest(model: model, contextOptions: ContextOptions(reasoningLevel: .custom("xhigh")))

        #expect(defaultBody["reasoning"] == .object(["effort": .string("low")]))
        #expect(deepBody["reasoning"] == .object(["effort": .string("high")]))
        #expect(customBody["reasoning"] == .object(["effort": .string("xhigh")]))
        #expect(defaultBody["include"] == .array([.string("reasoning.encrypted_content")]))
    }

    @Test func omitsReasoningEffortForModelsWithoutIt() throws {
        let body = try encodedRequest(model: .grok4_20, contextOptions: ContextOptions(reasoningLevel: .deep))

        #expect(body["reasoning"] == nil)
        #expect(body["include"] == .array([.string("reasoning.encrypted_content")]))
    }

    @Test(arguments: [
        GrokModel.grok4_20,
        .grok4_20NonReasoning,
        .grokBuild,
        GrokModel(name: "grok-custom", supportedReasoningEfforts: []),
    ])
    func omitsReasoningEffortWhenNoEffortsAreSupported(model: GrokModel) throws {
        let modelEffort = try encodedRequest(model: model.reasoningEffort(.high))
        let requestLevel = try encodedRequest(model: model, contextOptions: ContextOptions(reasoningLevel: .light))

        #expect(modelEffort["reasoning"] == nil)
        #expect(requestLevel["reasoning"] == nil)
    }

    @Test func omitsReasoningForModelsThatDoNotReason() throws {
        let model = GrokModel(name: "grok-custom", capabilities: [.vision, .guidedGeneration, .toolCalling], supportedReasoningEfforts: [.low])

        let body = try encodedRequest(model: model.reasoningEffort(.low))

        #expect(body["reasoning"] == nil)
        #expect(body["include"] == nil)
    }

    @Test func sendsEffortsThatTheModelDoesNotList() throws {
        // The API handles efforts that a model doesn't support, by rejecting
        // them or, for xhigh on older models, treating them as high, so the
        // request doesn't filter them.
        let body = try encodedRequest(model: GrokModel.grok4_5.reasoningEffort(.xhigh))
        let custom = try encodedRequest(model: GrokModel(name: "grok-custom", supportedReasoningEfforts: [.high]).reasoningEffort(.low))
        let disabled = try encodedRequest(model: GrokModel.grok4_3.reasoningEffort(.disabled))

        #expect(body["reasoning"] == .object(["effort": .string("xhigh")]))
        #expect(custom["reasoning"] == .object(["effort": .string("low")]))
        #expect(disabled["reasoning"] == .object(["effort": .string("none")]))
    }

    @Test func omitsEncryptedReasoningForNonReasoningModels() throws {
        let body = try encodedRequest(model: .grok4_20NonReasoning)

        #expect(body["include"] == nil)
    }

    @Test func sendsImagesAsDataURLs() throws {
        let image = try #require(solidImage())
        let prompt = Transcript.Prompt(segments: [
            .text(.init(content: "Describe these.")),
            .attachment(.init(content: .image(.init(image)), label: "photo")),
        ])

        let body = try encodedRequest(transcript: Transcript(entries: [.prompt(prompt)]))

        let content = try #require(body["input"]?[0]?["content"])
        #expect(content[0] == .object(["type": .string("input_text"), "text": .string("Describe these.")]))
        #expect(content[1] == .object(["type": .string("input_text"), "text": .string("Image \"photo\":")]))
        #expect(content[2]?["type"] == .string("input_image"))
        #expect(content[2]?["image_url"]?.stringValue?.hasPrefix("data:image/jpeg;base64,") == true)
    }

    @Test func sendsImageFilesWithoutReencoding() throws {
        let image = try #require(solidImage())
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        let png = try #require(CIContext().pngRepresentation(of: CIImage(cgImage: image), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()))
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let prompt = Transcript.Prompt(segments: [.attachment(.init(content: .image(.init(imageURL: url))))])

        let body = try encodedRequest(transcript: Transcript(entries: [.prompt(prompt)]))

        #expect(body["input"]?[0]?["content"]?[0]?["image_url"] == .string("data:image/png;base64,\(png.base64EncodedString())"))
    }

    @Test func movesInstructionImagesIntoAUserMessage() throws {
        let image = try #require(solidImage())
        let instructions = Transcript.Instructions(
            segments: [.text(.init(content: "Compare with the reference.")), .attachment(.init(content: .image(.init(image))))],
            toolDefinitions: []
        )

        let body = try encodedRequest(transcript: Transcript(entries: [.instructions(instructions)]))

        #expect(body["input"]?[0] == .object([
            "type": .string("message"), "role": .string("system"), "content": .string("Compare with the reference."),
        ]))
        #expect(body["input"]?[1]?["role"] == .string("user"))
        #expect(body["input"]?[1]?["content"]?[0]?["type"] == .string("input_image"))
    }

    @Test func sendsStructuredContentAsJSON() throws {
        let content = GeneratedContent(properties: ["temperature": 23])
        let transcript = Transcript(entries: [
            .prompt(.init(segments: [.text(.init(content: "Weather?"))])),
            .toolCalls(.init([Transcript.ToolCall(id: "call_1", toolName: "getWeather", arguments: GeneratedContent(properties: ["city": "Paris"]))])),
            .toolOutput(.init(id: "call_1", toolName: "getWeather", segments: [.structure(.init(schemaName: "Weather", content: content))])),
        ])

        let body = try encodedRequest(transcript: transcript)

        #expect(body["input"]?[1]?["arguments"] == .string(#"{"city": "Paris"}"#))
        #expect(body["input"]?[2]?["output"] == .string(content.jsonString))
    }

    @Test func sanitizesFormatNames() {
        #expect(TextConfiguration.formatName(for: "Array<Int>") == "Array_Int_")
        #expect(TextConfiguration.formatName(for: "") == "response")
        #expect(TextConfiguration.formatName(for: String(repeating: "a", count: 100)).count == 64)
    }

    // MARK: Helpers

    private func encodedRequest(
        model: GrokModel = .grok4_3,
        transcript: Transcript = Transcript(entries: [.prompt(.init(segments: [.text(.init(content: "Hi"))]))]),
        tools: [Transcript.ToolDefinition] = [],
        options: GenerationOptions = GenerationOptions(),
        contextOptions: ContextOptions = ContextOptions()
    ) throws -> JSONValue {
        let request = LanguageModelExecutorGenerationRequest(
            id: UUID(),
            transcript: transcript,
            enabledTools: tools,
            generationOptions: options,
            contextOptions: contextOptions,
            metadata: [:]
        )
        return try JSONValue(encoding: ResponsesRequest(request: request, model: model))
    }

    private func solidImage() -> CGImage? {
        let context = CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        context?.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        return context?.makeImage()
    }
}
