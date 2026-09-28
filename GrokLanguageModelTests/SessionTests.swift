//
//  SessionTests.swift
//  GrokLanguageModelTests
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels
import Synchronization
import Testing
@testable import GrokLanguageModel

/// Tests that run `LanguageModelSession` against a mock server.
struct SessionTests {
    @Test func sendsTranscriptAndStreamsText() async throws {
        let server = MockServer(replies: [.events(Events.textResponse("Hello there!"))])
        let session = LanguageModelSession(model: server.model(), instructions: "Be friendly.")

        let response = try await session.respond(to: "Hi")

        #expect(response.content == "Hello there!")
        #expect(response.usage.input.totalTokenCount == 10)
        #expect(response.usage.input.cachedTokenCount == 2)
        #expect(response.usage.output.totalTokenCount == 20)
        #expect(response.usage.output.reasoningTokenCount == 5)

        let request = try #require(server.requests.first)
        #expect(request["model"] == .string("grok-4.3"))
        #expect(request["stream"] == .bool(true))
        #expect(request["store"] == .bool(false))
        #expect(request["text"] == nil)
        #expect(request["tools"] == nil)
        #expect(request["input"] == .array([
            .object(["type": .string("message"), "role": .string("system"), "content": .string("Be friendly.")]),
            .object(["type": .string("message"), "role": .string("user"), "content": .string("Hi")]),
        ]))
        #expect(request["prompt_cache_key"] == .string(session.transcript.first!.id))
    }

    @Test func streamsSnapshotsAsTextArrives() async throws {
        let deltas = ["The ", "quick ", "brown ", "fox ", "jumps ", "over ", "the ", "lazy ", "dog."]
        let text = deltas.joined()
        let events = [Events.created(), Events.itemAdded(0, type: "message")]
            + deltas.map { Events.textDelta(0, $0) }
            + [Events.messageDone(0, text: text), Events.completed()]
        let server = MockServer(replies: [.events(events, interval: 0.02)])
        let session = LanguageModelSession(model: server.model())

        var snapshots: [String] = []
        for try await snapshot in session.streamResponse(to: "Hi") {
            snapshots.append(snapshot.content)
        }

        // The framework can combine fragments that arrive close together into
        // one snapshot, and can repeat a snapshot's content, so the test doesn't
        // expect one snapshot per delta. It expects the text to grow across
        // several snapshots, which doesn't happen if fragments don't report
        // token counts: then the only snapshots hold the finished text.
        let distinct = snapshots.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }
        #expect(snapshots.last == text)
        #expect(distinct.count >= 3, "Snapshots: \(snapshots)")
        #expect(zip(distinct, distinct.dropFirst()).allSatisfy { $1.count > $0.count && $1.hasPrefix($0) })
    }

    @Test func sendsPreviousResponsesInLaterRequests() async throws {
        let server = MockServer(replies: [
            .events(Events.textResponse("Nice to meet you.")),
            .events(Events.textResponse("Your name is Ada.")),
        ])
        let session = LanguageModelSession(model: server.model())

        try await session.respond(to: "I'm Ada.")
        try await session.respond(to: "What's my name?")

        let input = try #require(server.requests.last?["input"])
        #expect(input == .array([
            .object(["type": .string("message"), "role": .string("user"), "content": .string("I'm Ada.")]),
            .object(["type": .string("message"), "role": .string("assistant"), "content": .string("Nice to meet you.")]),
            .object(["type": .string("message"), "role": .string("user"), "content": .string("What's my name?")]),
        ]))
        #expect(server.requests.first?["prompt_cache_key"] == server.requests.last?["prompt_cache_key"])
    }

    @Test func requestsStructuredOutput() async throws {
        let json = #"{"name":"Paris","country":"France","population":2100000,"landmarks":["Eiffel Tower"]}"#
        let server = MockServer(replies: [.events(Events.textResponse(json))])
        let session = LanguageModelSession(model: server.model())

        let response = try await session.respond(to: "Facts about Paris", generating: CityFacts.self)

        #expect(response.content.name == "Paris")
        #expect(response.content.population == 2_100_000)
        #expect(response.content.landmarks == ["Eiffel Tower"])

        let format = try #require(server.requests.first?["text"]?["format"])
        #expect(format["type"] == .string("json_schema"))
        #expect(format["name"] == .string("CityFacts"))
        #expect(format["strict"] == .bool(true))
        #expect(format["schema"]?["properties"]?["population"]?["type"] == .string("integer"))
    }

    @Test func runsToolsAndSendsTheirOutput() async throws {
        let server = MockServer(replies: [
            .events([
                Events.created(),
                Events.itemAdded(0, type: "function_call", callID: "call_1", name: "getWeather"),
                Events.argumentsDelta(0, #"{"city":"Paris"}"#),
                Events.functionCallDone(0, callID: "call_1", name: "getWeather", arguments: #"{"city":"Paris"}"#),
                Events.completed(),
            ]),
            .events(Events.textResponse("It's sunny in Paris.")),
        ])
        let tool = WeatherTool()
        let session = LanguageModelSession(model: server.model(), tools: [tool])

        let response = try await session.respond(to: "Weather in Paris?")

        #expect(response.content == "It's sunny in Paris.")
        #expect(tool.cities == ["Paris"])

        let firstRequest = try #require(server.requests.first)
        #expect(firstRequest["tools"]?[0]?["type"] == .string("function"))
        #expect(firstRequest["tools"]?[0]?["name"] == .string("getWeather"))
        #expect(firstRequest["tools"]?[0]?["description"] == .string("Gets the current weather for a city."))
        #expect(firstRequest["tools"]?[0]?["parameters"]?["properties"]?["city"]?["type"] == .string("string"))

        let input = try #require(server.requests.last?["input"])
        #expect(input[1]?["type"] == .string("function_call"))
        #expect(input[1]?["call_id"] == .string("call_1"))
        #expect(input[1]?["name"] == .string("getWeather"))
        #expect(try decodedJSON(input[1]?["arguments"]) == .object(["city": .string("Paris")]))
        #expect(input[2]?["type"] == .string("function_call_output"))
        #expect(input[2]?["call_id"] == .string("call_1"))
        #expect(input[2]?["output"] == .string("It's 23°C and sunny in Paris."))
    }

    @Test func leavesToolsOutWhenToolCallingIsDisallowed() async throws {
        let server = MockServer(replies: [.events(Events.textResponse("Hello."))])
        let session = LanguageModelSession(model: server.model(), tools: [WeatherTool()])

        try await session.respond(to: "Hi", options: GenerationOptions(toolCallingMode: .disallowed))

        // The session doesn't pass its tools to the executor, so the request
        // has no tools and no tool choice.
        let request = try #require(server.requests.first)
        #expect(request["tools"] == nil)
        #expect(request["tool_choice"] == nil)
    }

    @Test func recordsReasoningAndSendsItBack() async throws {
        let server = MockServer(replies: [
            .events([
                Events.created(),
                Events.itemAdded(0, type: "reasoning"),
                Events.reasoningDelta(0, "Thinking it over."),
                Events.reasoningDone(0, summary: "Thinking it over.", encryptedContent: "ENCRYPTED"),
                Events.itemAdded(1, type: "message"),
                Events.textDelta(1, "Done."),
                Events.completed(),
            ]),
            .events(Events.textResponse("Again.")),
        ])
        let session = LanguageModelSession(model: server.model())

        try await session.respond(to: "First")

        let reasoning = try #require(session.transcript.compactMap { entry -> Transcript.Reasoning? in
            if case .reasoning(let reasoning) = entry { reasoning } else { nil }
        }.first)
        #expect(reasoning.segments.map(\.description).joined().contains("Thinking it over."))
        #expect(reasoning.metadata["responseID"] != nil)

        try await session.respond(to: "Second")

        let input = try #require(server.requests.last?["input"])
        #expect(input[1] == .object([
            "type": .string("reasoning"),
            "summary": .array([.object(["type": .string("summary_text"), "text": .string("Thinking it over.")])]),
            "encrypted_content": .string("ENCRYPTED"),
        ]))
    }

    @Test func doesNotSendReasoningToADifferentModel() async throws {
        let server = MockServer(replies: [
            .events([
                Events.created(),
                Events.itemAdded(0, type: "reasoning"),
                Events.reasoningDone(0, summary: "Hmm.", encryptedContent: "ENCRYPTED"),
                Events.itemAdded(1, type: "message"),
                Events.textDelta(1, "Done."),
                Events.completed(),
            ]),
            .events(Events.textResponse("Again.")),
        ])
        let first = LanguageModelSession(model: server.model(.grok4_3))
        try await first.respond(to: "First")

        let second = LanguageModelSession(model: server.model(.grok4_7), transcript: first.transcript)
        try await second.respond(to: "Second")

        let types = server.requests.last?["input"].flatMap { input -> [String]? in
            guard case .array(let items) = input else { return nil }
            return items.compactMap { $0["type"]?.stringValue }
        }
        #expect(types == ["message", "message", "message"])
    }

    @Test func reportsTheUsageFromTheAPI() async throws {
        let reasoning = String(repeating: "Let me think about that. ", count: 20)
        let text = String(repeating: "Here's the answer. ", count: 20)
        let server = MockServer(replies: [
            .events([
                Events.created(),
                Events.itemAdded(0, type: "reasoning"),
                Events.reasoningDelta(0, reasoning),
                Events.reasoningDone(0, summary: reasoning, encryptedContent: "ENCRYPTED"),
                Events.itemAdded(1, type: "message"),
                Events.textDelta(1, text),
                Events.messageDone(1, text: text),
                Events.completed(input: 10, cached: 2, output: 20, reasoning: 5),
            ]),
        ])
        let session = LanguageModelSession(model: server.model())

        let response = try await session.respond(to: "Hi")

        // The package estimates token counts while text streams in, and the
        // counts that the API reports at the end replace the estimates.
        #expect(response.usage.input.totalTokenCount == 10)
        #expect(response.usage.output.totalTokenCount == 20)
        #expect(response.usage.output.reasoningTokenCount == 5)
        #expect(session.usage.output.totalTokenCount == 20)
        #expect(session.usage.output.reasoningTokenCount == 5)
    }

    @Test(.timeLimit(.minutes(1)))
    func endsTheStreamWithoutAnErrorWhenCancelled() async throws {
        let deltas = (0..<50).map { "word\($0) " }
        let events = [Events.created(), Events.itemAdded(0, type: "message")]
            + deltas.map { Events.textDelta(0, $0) }
            + [Events.messageDone(0, text: deltas.joined()), Events.completed()]
        let server = MockServer(replies: [.events(events, interval: 0.02)])
        let session = LanguageModelSession(model: server.model())
        let snapshotCount = Mutex(0)

        let task = Task {
            for try await _ in session.streamResponse(to: "Hi") {
                snapshotCount.withLock { $0 += 1 }
            }
        }
        while snapshotCount.withLock({ $0 }) < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()

        // The task throws if the loop does.
        try await task.value
    }

    @Test func mapsTimeoutsToLanguageModelError() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TimingOutURLProtocol.self]
        var model = GrokModel.grok4_3
        model.configuration = GrokConfiguration(apiKey: "test-key", urlSession: URLSession(configuration: configuration))
        let session = LanguageModelSession(model: model)

        await #expect {
            try await session.respond(to: "Hi")
        } throws: { error in
            guard case LanguageModelError.timeout = error else { return false }
            return true
        }
    }

    @Test func mapsRateLimitsToLanguageModelError() async throws {
        let server = MockServer(replies: [
            .error(statusCode: 429, headers: ["Retry-After": "30"], json: #"{"code":"rate-limited","error":"Too many requests"}"#),
        ])
        let session = LanguageModelSession(model: server.model())

        await #expect {
            try await session.respond(to: "Hi")
        } throws: { error in
            guard case LanguageModelError.rateLimited(let context) = error else { return false }
            return context.resetDate != nil && context.debugDescription == "Too many requests"
        }
    }

    @Test func reportsRequestErrors() async throws {
        let server = MockServer(replies: [
            .error(statusCode: 400, json: #"{"code":"invalid-argument","error":"Bad request"}"#),
        ])
        let session = LanguageModelSession(model: server.model())

        await #expect {
            try await session.respond(to: "Hi")
        } throws: { error in
            guard case GrokError.requestFailed(400, "invalid-argument", "Bad request") = error else { return false }
            return true
        }
    }

    @Test func reportsFailuresDuringGeneration() async throws {
        let server = MockServer(replies: [
            .events([
                Events.created(),
                #"{"type":"response.failed","response":{"id":"resp_1","error":{"code":"server_error","message":"Model crashed"}}}"#,
            ]),
        ])
        let session = LanguageModelSession(model: server.model())

        await #expect {
            try await session.respond(to: "Hi")
        } throws: { error in
            guard case GrokError.generationFailed("server_error", "Model crashed") = error else { return false }
            return true
        }
    }

    private func decodedJSON(_ value: JSONValue?) throws -> JSONValue {
        let string = try #require(value?.stringValue)
        return try JSONDecoder().decode(JSONValue.self, from: Data(string.utf8))
    }
}

/// A URL protocol that fails every request with a timeout.
private final class TimingOutURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
    }

    override func stopLoading() {}
}
