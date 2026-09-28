//
//  ResponseStream.swift
//  GrokLanguageModel
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels

// MARK: - Stream events

/// An event that the xAI Responses API streams, like `response.output_text.delta`.
///
/// Only the fields that the translator uses are decoded, and every field is
/// optional so that unexpected shapes don't fail the stream.
struct StreamEvent: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        var type: String?
        var callID: String?
        var name: String?
        var arguments: String?
        var encryptedContent: String?
        var summary: [TextPart]?
        var content: [TextPart]?

        enum CodingKeys: String, CodingKey {
            case type, name, arguments, summary, content
            case callID = "call_id"
            case encryptedContent = "encrypted_content"
        }
    }

    struct TextPart: Decodable, Sendable {
        var type: String?
        var text: String?
    }

    struct Response: Decodable, Sendable {
        var id: String?
        var model: String?
        var usage: Usage?
        var error: JSONValue?
        var incompleteDetails: IncompleteDetails?

        enum CodingKeys: String, CodingKey {
            case id, model, usage, error
            case incompleteDetails = "incomplete_details"
        }
    }

    struct Usage: Decodable, Sendable {
        struct InputDetails: Decodable, Sendable {
            var cachedTokens: Int?
            enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens" }
        }

        struct OutputDetails: Decodable, Sendable {
            var reasoningTokens: Int?
            enum CodingKeys: String, CodingKey { case reasoningTokens = "reasoning_tokens" }
        }

        var inputTokens: Int?
        var inputTokensDetails: InputDetails?
        var outputTokens: Int?
        var outputTokensDetails: OutputDetails?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case inputTokensDetails = "input_tokens_details"
            case outputTokens = "output_tokens"
            case outputTokensDetails = "output_tokens_details"
        }
    }

    struct IncompleteDetails: Decodable, Sendable {
        var reason: String?
    }

    var type: String
    var delta: String?
    var outputIndex: Int?
    var summaryIndex: Int?
    var item: Item?
    var response: Response?
    var code: JSONValue?
    var message: String?
    var error: JSONValue?

    enum CodingKeys: String, CodingKey {
        case type, delta, item, response, code, message, error
        case outputIndex = "output_index"
        case summaryIndex = "summary_index"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        delta = try? container.decodeIfPresent(String.self, forKey: .delta)
        outputIndex = try? container.decodeIfPresent(Int.self, forKey: .outputIndex)
        summaryIndex = try? container.decodeIfPresent(Int.self, forKey: .summaryIndex)
        item = try? container.decodeIfPresent(Item.self, forKey: .item)
        response = try? container.decodeIfPresent(Response.self, forKey: .response)
        code = try? container.decodeIfPresent(JSONValue.self, forKey: .code)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        error = try? container.decodeIfPresent(JSONValue.self, forKey: .error)
    }

    /// Decodes the event in a server-sent event, or returns `nil` if it isn't one,
    /// like the `[DONE]` sentinel.
    init?(_ event: ServerSentEvent, decoder: JSONDecoder = JSONDecoder()) {
        guard let decoded = try? decoder.decode(StreamEvent.self, from: Data(event.data.utf8)) else { return nil }
        self = decoded
    }
}

// MARK: - Translation

/// A transcript entry that stream output targets.
enum EntryReference: Hashable, Sendable {
    case reasoning(String)
    case response(String)
    case toolCalls(String)
}

/// Token counts for a single response.
struct TokenUsage: Equatable, Sendable {
    var inputTokens = 0
    var cachedInputTokens = 0
    var outputTokens = 0
    var reasoningTokens = 0
}

/// An update to the transcript, which maps to a generation channel event.
enum StreamOutput: Equatable, Sendable {
    case reasoningText(entryID: String, text: String)
    case reasoningSignature(entryID: String, signature: Data)
    case responseText(entryID: String, text: String)
    case toolCallArguments(entryID: String, callID: String, name: String, arguments: String)
    case metadata(EntryReference, model: String, responseID: String)
    case usage(EntryReference, TokenUsage)
}

/// Translates the events of one Responses API stream into transcript updates.
struct ResponseStreamTranslator {
    private enum ItemKind {
        case reasoning, message, functionCall
    }

    private struct ItemState {
        var kind: ItemKind
        var entryID: String
        var hasOutput = false
        var summaryIndex: Int?
        var callID = ""
        var name = ""
    }

    let modelName: String
    private(set) var isComplete = false
    private var items: [Int: ItemState] = [:]
    private var toolCallsEntryID: String?
    private var entriesWithMetadata: Set<EntryReference> = []
    private var lastEntry: EntryReference?
    private var responseModel: String?
    private var responseID: String?

    init(modelName: String) {
        self.modelName = modelName
    }

    mutating func translate(_ event: StreamEvent) throws -> [StreamOutput] {
        switch event.type {
        case "response.created", "response.in_progress":
            responseID = event.response?.id ?? responseID
            responseModel = event.response?.model ?? responseModel
            return []

        case "response.output_item.added":
            if let index = event.outputIndex, let kind = itemKind(event.item?.type) {
                items[index] = newItem(kind: kind, from: event.item)
            }
            return []

        case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
            guard let delta = event.delta, !delta.isEmpty, let index = event.outputIndex else { return [] }
            var item = items[index] ?? newItem(kind: .reasoning, from: nil)
            var text = delta
            if let summaryIndex = event.summaryIndex {
                if item.hasOutput, let previous = item.summaryIndex, previous != summaryIndex {
                    text = "\n\n" + text
                }
                item.summaryIndex = summaryIndex
            }
            item.hasOutput = true
            items[index] = item
            return record(.reasoning(item.entryID), .reasoningText(entryID: item.entryID, text: text))

        case "response.output_text.delta":
            guard let delta = event.delta, !delta.isEmpty, let index = event.outputIndex else { return [] }
            var item = items[index] ?? newItem(kind: .message, from: nil)
            item.hasOutput = true
            items[index] = item
            return record(.response(item.entryID), .responseText(entryID: item.entryID, text: delta))

        case "response.function_call_arguments.delta":
            guard let delta = event.delta, !delta.isEmpty,
                  let index = event.outputIndex, var item = items[index], item.kind == .functionCall
            else { return [] }
            item.hasOutput = true
            items[index] = item
            return record(
                .toolCalls(item.entryID),
                .toolCallArguments(entryID: item.entryID, callID: item.callID, name: item.name, arguments: delta)
            )

        case "response.output_item.done":
            return itemDone(event)

        case "response.completed":
            isComplete = true
            return usageOutput(event.response?.usage)

        case "response.incomplete":
            let reason = event.response?.incompleteDetails?.reason ?? "unknown"
            if reason == "content_filter" {
                throw LanguageModelError.guardrailViolation(.init(
                    debugDescription: "The xAI API stopped the response because of its content filter."
                ))
            }
            // Keep partial output, like when the response reaches `max_output_tokens`.
            isComplete = true
            return usageOutput(event.response?.usage)

        case "response.failed":
            throw Self.generationError(event.response?.error, fallbackCode: nil, fallbackMessage: nil)

        case "error":
            throw Self.generationError(event.error, fallbackCode: event.code?.textValue, fallbackMessage: event.message)

        default:
            return []
        }
    }

    /// Validates that the stream finished with a terminal event.
    func finish() throws {
        guard isComplete else {
            throw GrokError.invalidResponse("The response stream ended before the response completed.")
        }
    }

    // MARK: Items

    private func itemKind(_ type: String?) -> ItemKind? {
        switch type {
        case "reasoning": .reasoning
        case "message": .message
        case "function_call": .functionCall
        default: nil
        }
    }

    private mutating func newItem(kind: ItemKind, from item: StreamEvent.Item?) -> ItemState {
        switch kind {
        case .reasoning, .message:
            return ItemState(kind: kind, entryID: UUID().uuidString)
        case .functionCall:
            // All the tool calls in a response belong to one tool calls entry.
            let entryID = toolCallsEntryID ?? UUID().uuidString
            toolCallsEntryID = entryID
            return ItemState(
                kind: kind,
                entryID: entryID,
                callID: item?.callID ?? UUID().uuidString,
                name: item?.name ?? ""
            )
        }
    }

    private mutating func itemDone(_ event: StreamEvent) -> [StreamOutput] {
        guard let index = event.outputIndex, let doneItem = event.item, let kind = itemKind(doneItem.type) else { return [] }
        let item = items[index] ?? newItem(kind: kind, from: doneItem)
        items[index] = item
        var outputs: [StreamOutput] = []

        switch kind {
        case .reasoning:
            // Fall back to the finished item's text if no deltas streamed.
            if !item.hasOutput {
                let text = (doneItem.summary ?? doneItem.content ?? []).compactMap(\.text).joined(separator: "\n\n")
                if !text.isEmpty {
                    outputs += record(.reasoning(item.entryID), .reasoningText(entryID: item.entryID, text: text))
                }
            }
            if let encryptedContent = doneItem.encryptedContent, !encryptedContent.isEmpty {
                let signature = ReasoningSignature(model: modelName, encryptedContent: encryptedContent)
                outputs += record(.reasoning(item.entryID), .reasoningSignature(entryID: item.entryID, signature: signature.data))
            }

        case .message:
            if !item.hasOutput {
                let text = (doneItem.content ?? []).filter { $0.type == "output_text" }.compactMap(\.text).joined()
                if !text.isEmpty {
                    outputs += record(.response(item.entryID), .responseText(entryID: item.entryID, text: text))
                }
            }

        case .functionCall:
            if !item.hasOutput {
                let arguments = doneItem.arguments.flatMap { $0.isEmpty ? nil : $0 } ?? "{}"
                outputs += record(
                    .toolCalls(item.entryID),
                    .toolCallArguments(
                        entryID: item.entryID,
                        callID: doneItem.callID ?? item.callID,
                        name: doneItem.name ?? item.name,
                        arguments: arguments
                    )
                )
            }
        }
        items[index]?.hasOutput = true
        return outputs
    }

    /// Returns the output for an entry, preceded by the entry's metadata the
    /// first time the entry receives output.
    private mutating func record(_ entry: EntryReference, _ output: StreamOutput) -> [StreamOutput] {
        lastEntry = entry
        var outputs = [output]
        if let responseID, !entriesWithMetadata.contains(entry) {
            entriesWithMetadata.insert(entry)
            outputs.append(.metadata(entry, model: responseModel ?? modelName, responseID: responseID))
        }
        return outputs
    }

    private mutating func usageOutput(_ usage: StreamEvent.Usage?) -> [StreamOutput] {
        guard let usage else { return [] }
        let tokenUsage = TokenUsage(
            inputTokens: usage.inputTokens ?? 0,
            cachedInputTokens: usage.inputTokensDetails?.cachedTokens ?? 0,
            outputTokens: usage.outputTokens ?? 0,
            reasoningTokens: usage.outputTokensDetails?.reasoningTokens ?? 0
        )
        // Attribute the response's usage to its last entry, creating an empty
        // response entry if the model produced no output.
        let entry = lastEntry ?? .response(UUID().uuidString)
        return [.usage(entry, tokenUsage)]
    }

    private static func generationError(_ error: JSONValue?, fallbackCode: String?, fallbackMessage: String?) -> GrokError {
        let code = error?["code"]?.textValue ?? fallbackCode
        let message = error?["message"]?.stringValue ?? error?.stringValue ?? fallbackMessage ?? "Unknown error"
        return .generationFailed(code: code, message: message)
    }
}

// MARK: - Channel events

extension StreamOutput {
    /// Estimates the number of tokens in a fragment of streamed text.
    ///
    /// The framework uses the token counts of the fragments that an executor
    /// sends to decide when to publish `ResponseStream` snapshots, and doesn't
    /// publish any for fragments with a count of `0` until the response
    /// completes. The xAI API doesn't report token counts for individual
    /// deltas, so this estimates roughly one token per four UTF-8 bytes, and
    /// at least one token for every fragment.
    ///
    /// The estimate only paces snapshots and approximates the usage that
    /// snapshots report while the response streams. The usage that the API
    /// reports when the response completes, which the translator sends as a
    /// usage update, replaces it and remains authoritative for the response's
    /// token counts.
    static func estimatedTokenCount(for text: String) -> Int {
        max(1, (text.utf8.count + 3) / 4)
    }

    var channelEvent: LanguageModelExecutorGenerationChannel.Event {
        switch self {
        case .reasoningText(let entryID, let text):
            return .reasoning(entryID: entryID, action: .appendText(text, tokenCount: Self.estimatedTokenCount(for: text)))
        case .reasoningSignature(let entryID, let signature):
            // The signature is opaque encrypted reasoning rather than generated
            // text, so it doesn't add to the usage that snapshots report.
            return .reasoning(entryID: entryID, action: .updateSignature(signature, tokenCount: 0))
        case .responseText(let entryID, let text):
            return .response(entryID: entryID, action: .appendText(text, tokenCount: Self.estimatedTokenCount(for: text)))
        case .toolCallArguments(let entryID, let callID, let name, let arguments):
            let tokenCount = Self.estimatedTokenCount(for: arguments)
            return .toolCalls(
                entryID: entryID,
                action: .toolCall(id: callID, name: name, action: .appendArguments(arguments, tokenCount: tokenCount))
            )
        case .metadata(let entry, let model, let responseID):
            let values: [String: any ConvertibleToGeneratedContent] = ["model": model, "responseID": responseID]
            switch entry {
            case .reasoning(let entryID): return .reasoning(entryID: entryID, action: .updateMetadata(values))
            case .response(let entryID): return .response(entryID: entryID, action: .updateMetadata(values))
            case .toolCalls(let entryID): return .toolCalls(entryID: entryID, action: .updateMetadata(values))
            }
        case .usage(let entry, let usage):
            let input = LanguageModelExecutorGenerationChannel.Usage.Input(
                totalTokenCount: usage.inputTokens,
                cachedTokenCount: usage.cachedInputTokens
            )
            let output = LanguageModelExecutorGenerationChannel.Usage.Output(
                totalTokenCount: usage.outputTokens,
                reasoningTokenCount: usage.reasoningTokens
            )
            switch entry {
            case .reasoning(let entryID): return .reasoning(entryID: entryID, action: .updateUsage(input: input, output: output))
            case .response(let entryID): return .response(entryID: entryID, action: .updateUsage(input: input, output: output))
            case .toolCalls(let entryID): return .toolCalls(entryID: entryID, action: .updateUsage(input: input, output: output))
            }
        }
    }
}
