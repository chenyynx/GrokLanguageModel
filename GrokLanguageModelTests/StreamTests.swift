//
//  StreamTests.swift
//  GrokLanguageModelTests
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels
import Testing
@testable import GrokLanguageModel

struct ServerSentEventParserTests {
    @Test func parsesEvents() {
        let stream = "event: first\r\ndata: {\"a\":1}\r\n\r\n: keep-alive\n\ndata: line one\ndata: line two\n\ndata: [DONE]"

        var parser = ServerSentEventParser()
        var events = Array(stream.utf8).compactMap { parser.consume($0) }
        if let last = parser.finish() {
            events.append(last)
        }

        #expect(events == [
            ServerSentEvent(event: "first", data: #"{"a":1}"#),
            ServerSentEvent(event: nil, data: "line one\nline two"),
            ServerSentEvent(event: nil, data: "[DONE]"),
        ])
        #expect(StreamEvent(events[2]) == nil)
    }

    @Test func decodesMultibyteCharacters() {
        var parser = ServerSentEventParser()
        let events = Array("data: 23°C ☀️\n\n".utf8).compactMap { parser.consume($0) }

        #expect(events == [ServerSentEvent(event: nil, data: "23°C ☀️")])
    }
}

struct ResponseStreamTranslatorTests {
    @Test func translatesReasoningAndText() throws {
        let outputs = try translate([
            Events.created(),
            Events.itemAdded(0, type: "reasoning"),
            Events.reasoningDelta(0, "First part.", summaryIndex: 0),
            Events.reasoningDelta(0, "Second part.", summaryIndex: 1),
            Events.reasoningDone(0, summary: "ignored", encryptedContent: "SECRET"),
            Events.itemAdded(1, type: "message"),
            Events.textDelta(1, "Hello"),
            Events.textDelta(1, " world"),
            Events.messageDone(1, text: "Hello world"),
            Events.completed(input: 7, cached: 1, output: 9, reasoning: 4),
        ])

        guard case .reasoningText(let reasoningID, "First part.") = outputs[0],
              case .responseText(let responseID, "Hello") = outputs[4]
        else {
            Issue.record("Unexpected outputs: \(outputs)")
            return
        }
        let signature = ReasoningSignature(model: "grok-4.3", encryptedContent: "SECRET").data
        #expect(outputs == [
            .reasoningText(entryID: reasoningID, text: "First part."),
            .metadata(.reasoning(reasoningID), model: "grok-4.3", responseID: "resp_1"),
            .reasoningText(entryID: reasoningID, text: "\n\nSecond part."),
            .reasoningSignature(entryID: reasoningID, signature: signature),
            .responseText(entryID: responseID, text: "Hello"),
            .metadata(.response(responseID), model: "grok-4.3", responseID: "resp_1"),
            .responseText(entryID: responseID, text: " world"),
            .usage(.response(responseID), TokenUsage(inputTokens: 7, cachedInputTokens: 1, outputTokens: 9, reasoningTokens: 4)),
        ])
        #expect(reasoningID != responseID)
    }

    @Test func groupsToolCallsIntoOneEntry() throws {
        let outputs = try translate([
            Events.created(),
            Events.itemAdded(0, type: "function_call", callID: "call_a", name: "lookup"),
            Events.argumentsDelta(0, #"{"q":"a"}"#),
            Events.functionCallDone(0, callID: "call_a", name: "lookup", arguments: #"{"q":"a"}"#),
            Events.itemAdded(1, type: "function_call", callID: "call_b", name: "lookup"),
            Events.functionCallDone(1, callID: "call_b", name: "lookup", arguments: ""),
            Events.completed(),
        ])

        guard case .toolCallArguments(let entryID, _, _, _) = outputs[0] else {
            Issue.record("Unexpected outputs: \(outputs)")
            return
        }
        #expect(outputs == [
            .toolCallArguments(entryID: entryID, callID: "call_a", name: "lookup", arguments: #"{"q":"a"}"#),
            .metadata(.toolCalls(entryID), model: "grok-4.3", responseID: "resp_1"),
            .toolCallArguments(entryID: entryID, callID: "call_b", name: "lookup", arguments: "{}"),
            .usage(.toolCalls(entryID), TokenUsage(inputTokens: 10, cachedInputTokens: 2, outputTokens: 20, reasoningTokens: 5)),
        ])
    }

    @Test func usesFinishedItemsWhenNothingStreamed() throws {
        let outputs = try translate([
            Events.created(),
            Events.messageDone(0, text: "All at once."),
            Events.completed(),
        ])

        guard case .responseText(let entryID, "All at once.") = outputs.first else {
            Issue.record("Unexpected outputs: \(outputs)")
            return
        }
        #expect(outputs.count == 3)
        #expect(outputs.last == .usage(.response(entryID), TokenUsage(inputTokens: 10, cachedInputTokens: 2, outputTokens: 20, reasoningTokens: 5)))
    }

    @Test func keepsPartialOutputWhenTheResponseIsTruncated() throws {
        var translator = ResponseStreamTranslator(modelName: "grok-4.3")
        _ = try translator.translate(event(Events.created()))
        _ = try translator.translate(event(Events.textDelta(0, "Partial")))
        _ = try translator.translate(event(
            #"{"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}"#
        ))

        #expect(translator.isComplete)
        try translator.finish()
    }

    @Test func throwsForContentFilterStops() throws {
        var translator = ResponseStreamTranslator(modelName: "grok-4.3")

        #expect {
            try translator.translate(event(
                #"{"type":"response.incomplete","response":{"incomplete_details":{"reason":"content_filter"}}}"#
            ))
        } throws: { error in
            guard case LanguageModelError.guardrailViolation = error else { return false }
            return true
        }
    }

    @Test func throwsForErrorEvents() throws {
        var translator = ResponseStreamTranslator(modelName: "grok-4.3")

        #expect {
            try translator.translate(event(#"{"type":"error","code":"overloaded","message":"Try again later"}"#))
        } throws: { error in
            guard case GrokError.generationFailed("overloaded", "Try again later") = error else { return false }
            return true
        }
    }

    @Test func throwsWhenTheStreamEndsEarly() throws {
        var translator = ResponseStreamTranslator(modelName: "grok-4.3")
        _ = try translator.translate(event(Events.textDelta(0, "Cut off")))

        #expect(throws: GrokError.self) {
            try translator.finish()
        }
    }

    @Test(arguments: [
        ("", 1),
        ("a", 1),
        ("Hello", 2),
        ("Hello, world", 3),
        ("23°C ☀️", 3),
        (String(repeating: "x", count: 400), 100),
    ])
    func estimatesAtLeastOneTokenPerFragment(text: String, tokenCount: Int) {
        #expect(StreamOutput.estimatedTokenCount(for: text) == tokenCount)
    }

    // MARK: Helpers

    private func translate(_ events: [String]) throws -> [StreamOutput] {
        var translator = ResponseStreamTranslator(modelName: "grok-4.3")
        let outputs = try events.flatMap { try translator.translate(event($0)) }
        try translator.finish()
        return outputs
    }

    private func event(_ json: String) throws -> StreamEvent {
        try #require(StreamEvent(ServerSentEvent(event: nil, data: json)))
    }
}
