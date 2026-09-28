//
//  ResponsesRequest.swift
//  GrokLanguageModel
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels

/// The body of a streaming request to the xAI Responses API.
struct ResponsesRequest: Encodable, Sendable {
    var model: String
    var input: [InputItem]
    var stream = true
    /// The session keeps the transcript, so the server doesn't need to store it.
    var store = false
    var include: [String]?
    var tools: [FunctionTool]?
    var toolChoice: String?
    var text: TextConfiguration?
    var reasoning: ReasoningConfiguration?
    var temperature: Double?
    var topP: Double?
    var topK: Int?
    var maxOutputTokens: Int?
    var promptCacheKey: String?

    enum CodingKeys: String, CodingKey {
        case model, input, stream, store, include, tools, text, reasoning, temperature
        case toolChoice = "tool_choice"
        case topP = "top_p"
        case topK = "top_k"
        case maxOutputTokens = "max_output_tokens"
        case promptCacheKey = "prompt_cache_key"
    }
}

extension ResponsesRequest {
    init(request: LanguageModelExecutorGenerationRequest, model: GrokModel) throws {
        self.model = model.name
        self.input = try InputItem.items(from: request.transcript, modelName: model.name)

        let tools = try request.enabledToolDefinitions.map(FunctionTool.init)
        if !tools.isEmpty {
            self.tools = tools
            self.toolChoice = request.generationOptions.toolCallingMode.map(Self.toolChoice)
        }

        if let schema = request.schema {
            self.text = try TextConfiguration(schema: schema)
        }

        if model.capabilities.contains(.reasoning) {
            self.include = ["reasoning.encrypted_content"]
        }
        if model.supportsReasoningEffort {
            let effort = request.contextOptions.reasoningLevel.map(GrokModel.ReasoningEffort.init) ?? model.reasoningEffort
            self.reasoning = effort.map { ReasoningConfiguration(effort: $0.rawValue) }
        }

        let options = request.generationOptions
        self.temperature = options.temperature
        self.maxOutputTokens = options.maximumResponseTokens
        switch options.samplingMode?.kind {
        case .greedy:
            self.topK = 1
        case .randomTopK(let k, _):
            self.topK = k
        case .randomProbabilityThreshold(let threshold, _):
            self.topP = threshold
        case nil:
            break
        @unknown default:
            break
        }

        // Every request in a session starts with the same entry, so its ID
        // routes the session's requests to the same server for cache hits.
        self.promptCacheKey = request.transcript.first?.id
    }

    private static func toolChoice(for mode: GenerationOptions.ToolCallingMode) -> String {
        switch mode.kind {
        case .allowed: "auto"
        case .required: "required"
        // Sessions leave their tools out of `.disallowed` requests, so this
        // only applies to a request that lists tools anyway.
        case .disallowed: "none"
        @unknown default: "auto"
        }
    }
}

// MARK: - Input items

enum InputItem: Encodable, Equatable, Sendable {
    enum Role: String, Sendable {
        case system, user, assistant
    }

    case message(role: Role, content: [ContentPart])
    case functionCall(callID: String, name: String, arguments: String)
    case functionCallOutput(callID: String, output: [ContentPart])
    case reasoning(summary: String, encryptedContent: String)

    private enum CodingKeys: String, CodingKey {
        case type, role, content, name, arguments, output, summary
        case callID = "call_id"
        case encryptedContent = "encrypted_content"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let role, let content):
            try container.encode("message", forKey: .type)
            try container.encode(role.rawValue, forKey: .role)
            try container.encode(ContentPart.List(parts: content), forKey: .content)
        case .functionCall(let callID, let name, let arguments):
            try container.encode("function_call", forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(name, forKey: .name)
            try container.encode(arguments, forKey: .arguments)
        case .functionCallOutput(let callID, let output):
            try container.encode("function_call_output", forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(ContentPart.List(parts: output), forKey: .output)
        case .reasoning(let summary, let encryptedContent):
            try container.encode("reasoning", forKey: .type)
            let parts = summary.isEmpty ? [] : [SummaryText(text: summary)]
            try container.encode(parts, forKey: .summary)
            try container.encode(encryptedContent, forKey: .encryptedContent)
        }
    }

    private struct SummaryText: Encodable {
        var type = "summary_text"
        var text: String
    }
}

enum ContentPart: Equatable, Sendable {
    case text(String)
    case image(url: String)

    /// Content that encodes as a plain string when it's only text, and as a
    /// list of typed parts otherwise.
    struct List: Encodable {
        var parts: [ContentPart]

        func encode(to encoder: any Encoder) throws {
            let texts = parts.compactMap { part -> String? in
                if case .text(let text) = part { text } else { nil }
            }
            if texts.count == parts.count {
                var container = encoder.singleValueContainer()
                try container.encode(texts.joined(separator: "\n"))
                return
            }
            var container = encoder.unkeyedContainer()
            for part in parts {
                switch part {
                case .text(let text):
                    try container.encode(["type": "input_text", "text": text])
                case .image(let url):
                    try container.encode(["type": "input_image", "image_url": url])
                }
            }
        }
    }
}

extension InputItem {
    static func items(from transcript: Transcript, modelName: String) throws -> [InputItem] {
        var items: [InputItem] = []
        for entry in transcript {
            switch entry {
            case .instructions(let instructions):
                let text = ContentPart.text(from: instructions.segments)
                if !text.isEmpty {
                    items.append(.message(role: .system, content: [.text(text)]))
                }
                // The xAI API ignores images in system messages, so send them
                // in a user message instead.
                let attachments = instructions.segments.filter { if case .attachment = $0 { true } else { false } }
                if !attachments.isEmpty {
                    items.append(.message(role: .user, content: try ContentPart.parts(from: attachments)))
                }
            case .prompt(let prompt):
                items.append(.message(role: .user, content: try ContentPart.parts(from: prompt.segments)))
            case .response(let response):
                let text = ContentPart.text(from: response.segments)
                if !text.isEmpty {
                    items.append(.message(role: .assistant, content: [.text(text)]))
                }
            case .reasoning(let reasoning):
                if let signature = reasoning.signature,
                   let encryptedContent = ReasoningSignature(data: signature)?.encryptedContent(forModel: modelName) {
                    items.append(.reasoning(summary: ContentPart.text(from: reasoning.segments), encryptedContent: encryptedContent))
                }
            case .toolCalls(let toolCalls):
                for call in toolCalls {
                    items.append(.functionCall(callID: call.id, name: call.toolName, arguments: call.arguments.jsonString))
                }
            case .toolOutput(let output):
                items.append(.functionCallOutput(callID: output.id, output: try ContentPart.parts(from: output.segments)))
            @unknown default:
                throw LanguageModelError.unsupportedTranscriptContent(.init(
                    unsupportedContent: [entry],
                    debugDescription: "Grok models don't support this kind of transcript entry."
                ))
            }
        }
        return items
    }
}

extension ContentPart {
    static func parts(from segments: [Transcript.Segment]) throws -> [ContentPart] {
        var parts: [ContentPart] = []
        for segment in segments {
            switch segment {
            case .text(let text):
                parts.append(.text(text.content))
            case .structure(let structure):
                parts.append(.text(structure.content.jsonString))
            case .attachment(let attachment):
                switch attachment.content {
                case .image(let image):
                    if let label = attachment.label {
                        parts.append(.text("Image \"\(label)\":"))
                    }
                    parts.append(.image(url: try ImageEncoder.url(for: image)))
                @unknown default:
                    break
                }
            @unknown default:
                break
            }
        }
        return parts
    }

    /// The text of the segments, ignoring attachments.
    static func text(from segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment -> String? in
            switch segment {
            case .text(let text): text.content
            case .structure(let structure): structure.content.jsonString
            default: nil
            }
        }
        .joined(separator: "\n")
    }
}

// MARK: - Tools, formats, and reasoning

struct FunctionTool: Encodable, Equatable, Sendable {
    var type = "function"
    var name: String
    var description: String
    var parameters: JSONValue

    init(_ definition: Transcript.ToolDefinition) throws {
        self.name = definition.name
        self.description = definition.description
        self.parameters = try JSONValue(encoding: definition.parameters)
    }
}

struct TextConfiguration: Encodable, Equatable, Sendable {
    struct Format: Encodable, Equatable, Sendable {
        var type = "json_schema"
        var name: String
        var schema: JSONValue
        var strict = true
    }

    var format: Format

    init(schema: GenerationSchema) throws {
        self.format = Format(name: Self.formatName(for: schema.name), schema: try JSONValue(encoding: schema))
    }

    /// A schema name that only uses the characters that response format names allow.
    static func formatName(for name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let sanitized = String(name.map { allowed.contains($0) ? $0 : "_" }.prefix(64))
        return sanitized.isEmpty ? "response" : sanitized
    }
}

struct ReasoningConfiguration: Encodable, Equatable, Sendable {
    var effort: String
}

// MARK: - Reasoning signatures

/// The opaque signature stored on reasoning transcript entries.
///
/// It wraps the encrypted reasoning that the xAI API returns, and records the
/// model that produced it so that it's only sent back to the same model.
struct ReasoningSignature: Codable, Equatable, Sendable {
    var provider = "xai"
    var model: String
    var encryptedContent: String

    init(model: String, encryptedContent: String) {
        self.model = model
        self.encryptedContent = encryptedContent
    }

    init?(data: Data) {
        guard let signature = try? JSONDecoder().decode(ReasoningSignature.self, from: data) else { return nil }
        self = signature
    }

    var data: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)) ?? Data()
    }

    func encryptedContent(forModel model: String) -> String? {
        provider == "xai" && self.model == model ? encryptedContent : nil
    }
}
