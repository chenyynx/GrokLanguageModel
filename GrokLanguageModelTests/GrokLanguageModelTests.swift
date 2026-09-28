//
//  GrokLanguageModelTests.swift
//  GrokLanguageModelTests
//
//  Created by Marcus Arnett on 9/28/26.
//

import CoreGraphics
import Foundation
import FoundationModels
import Synchronization
import Testing
@testable import GrokLanguageModel

/// Live tests that send requests to the xAI API through `LanguageModelSession`.
///
/// These run when `GROK_API_KEY` or `XAI_API_KEY` is set in the environment,
/// or when `GROK_API_KEY` is set in the `.env` file at the root of the package.
@Suite(.serialized, .enabled(if: TestSupport.hasAPIKey, "Set GROK_API_KEY or XAI_API_KEY to run live tests"), .timeLimit(.minutes(5)))
struct GrokLanguageModelTests {
    @Test func respondsToPrompt() async throws {
        let model = GrokModel.grok4.reasoningEffort(.low).apiKey(try #require(TestSupport.apiKey))
        let session = LanguageModelSession(model: model, instructions: "Follow the user's formatting instructions exactly.")

        let response = try await session.respond(to: "Reply with only the word pong, in lowercase.")

        #expect(response.content.lowercased().contains("pong"))
        #expect(response.usage.input.totalTokenCount > 0)
        #expect(response.usage.output.totalTokenCount > 0)
        #expect(session.transcript.contains { if case .response = $0 { true } else { false } })
    }

    @Test func streamsResponse() async throws {
        let session = LanguageModelSession(model: TestSupport.fastModel)
        let clock = ContinuousClock()

        var snapshots: [(content: String, time: ContinuousClock.Instant)] = []
        for try await snapshot in session.streamResponse(to: "Count from 1 to 100, separated by commas, and nothing else.") {
            snapshots.append((snapshot.content, clock.now))
        }
        let end = clock.now

        let final = try #require(snapshots.last?.content)
        #expect(final.contains("100"))
        #expect(snapshots.count >= 5, "Received \(snapshots.count) snapshots")
        // The text arrives while the model generates it, not all at once when
        // the response completes: an early snapshot holds the first part of
        // the final text, well before the stream ends.
        let early = snapshots.first { snapshot in
            !snapshot.content.isEmpty && snapshot.content.count * 2 <= final.count && final.hasPrefix(snapshot.content)
        }
        let earlySnapshot = try #require(early, "No snapshot held less than half of the final text")
        #expect(end - earlySnapshot.time >= .milliseconds(250))
    }

    @Test func generatesStructuredOutput() async throws {
        let session = LanguageModelSession(model: TestSupport.fastModel)

        let response = try await session.respond(to: "Give me facts about Paris.", generating: CityFacts.self)

        #expect(response.content.name.localizedCaseInsensitiveContains("Paris"))
        #expect(response.content.country.localizedCaseInsensitiveContains("France"))
        #expect(response.content.population > 1_000_000)
        #expect(!response.content.landmarks.isEmpty)
    }

    @Test func streamsStructuredOutput() async throws {
        let session = LanguageModelSession(model: TestSupport.fastModel)

        var lastSnapshot: CityFacts.PartiallyGenerated?
        for try await snapshot in session.streamResponse(to: "Give me facts about Tokyo.", generating: CityFacts.self) {
            lastSnapshot = snapshot.content
        }

        let facts = try #require(lastSnapshot)
        #expect(facts.name?.localizedCaseInsensitiveContains("Tokyo") == true)
    }

    @Test func streamsPartialStructuredOutput() async throws {
        let session = LanguageModelSession(model: TestSupport.fastModel)

        var snapshots: [LanguageModelSession.ResponseStream<CityFacts>.Snapshot] = []
        for try await snapshot in session.streamResponse(to: "Give me facts about Rome.", generating: CityFacts.self) {
            snapshots.append(snapshot)
        }

        let final = try #require(snapshots.last)
        #expect(final.rawContent.isComplete)
        #expect(final.content.name?.localizedCaseInsensitiveContains("Rome") == true)
        #expect(final.content.landmarks?.isEmpty == false)
        #expect(snapshots.count >= 5, "Received \(snapshots.count) snapshots")
        // Partially generated content arrives before the response completes.
        let partial = snapshots.dropLast().filter { !$0.rawContent.isComplete }
        #expect(partial.count >= 3, "Received \(partial.count) partial snapshots")
        #expect(Set(partial.map(\.rawContent.jsonString)).count >= 3)
    }

    @Test func streamsPropertiesInDeclarationOrder() async throws {
        let session = LanguageModelSession(model: TestSupport.fastModel)

        // The properties of the first snapshot that has any, and the index of
        // the first snapshot that has each property.
        var firstProperties: Set<String>?
        var firstSnapshotIndex: [String: Int] = [:]
        var snapshotIndex = 0
        for try await snapshot in session.streamResponse(to: "Plan a short trip to Kyoto.", generating: TripPlan.self) {
            defer { snapshotIndex += 1 }
            guard case .structure(let properties, _) = snapshot.rawContent.kind, !properties.isEmpty else { continue }
            if firstProperties == nil {
                firstProperties = Set(properties.keys)
            }
            for name in properties.keys where firstSnapshotIndex[name] == nil {
                firstSnapshotIndex[name] = snapshotIndex
            }
        }

        // Grok generates properties in the order that the schema lists them,
        // so they arrive in declaration order rather than alphabetical order.
        // Properties can first appear in the same snapshot when the framework
        // combines fragments, so the indices only need to be nondecreasing.
        let declared = ["title", "destination", "nights", "activities", "summary"]
        let first = try #require(firstProperties, "No snapshot had any properties")
        #expect(first.contains("title"), "The first snapshot with properties had \(first.sorted())")
        let indices = declared.compactMap { firstSnapshotIndex[$0] }
        #expect(indices.count == declared.count, "Properties by first snapshot: \(firstSnapshotIndex)")
        #expect(indices == indices.sorted(), "Properties by first snapshot: \(firstSnapshotIndex)")
    }

    @Test func callsTools() async throws {
        let tool = WeatherTool()
        let session = LanguageModelSession(
            model: TestSupport.fastModel,
            tools: [tool],
            instructions: "Use the getWeather tool to answer questions about the weather."
        )

        let response = try await session.respond(to: "What's the weather like in Paris and in Rome right now?")

        #expect(Set(tool.cities.map { $0.lowercased() }) == ["paris", "rome"])
        #expect(response.content.contains("23"))
        let entries = Array(session.transcript)
        #expect(entries.contains { if case .toolCalls = $0 { true } else { false } })
        #expect(entries.contains { if case .toolOutput = $0 { true } else { false } })
    }

    @Test func remembersConversation() async throws {
        let session = LanguageModelSession(model: TestSupport.fastModel)

        try await session.respond(to: "My favorite color is teal. Just acknowledge it briefly.")
        let response = try await session.respond(to: "What's my favorite color? Answer with one word.")

        #expect(response.content.lowercased().contains("teal"))
    }

    @Test func recordsReasoning() async throws {
        let model = GrokModel.grok4.apiKey(try #require(TestSupport.apiKey))
        let session = LanguageModelSession(model: model)

        let first = try await session.respond(
            to: "What is 17 × 23? Reply with just the number.",
            contextOptions: ContextOptions(reasoningLevel: .light)
        )
        #expect(first.content.contains("391"))
        #expect(first.usage.output.reasoningTokenCount > 0)

        let reasoning = session.transcript.compactMap { entry -> Transcript.Reasoning? in
            if case .reasoning(let reasoning) = entry { reasoning } else { nil }
        }
        let signature = try #require(reasoning.first?.signature)
        #expect(ReasoningSignature(data: signature)?.encryptedContent(forModel: model.name) != nil)

        // The encrypted reasoning is sent back with the next request.
        let second = try await session.respond(
            to: "Now add 9 to that. Reply with just the number.",
            contextOptions: ContextOptions(reasoningLevel: .light)
        )
        #expect(second.content.contains("400"))
    }

    @Test func understandsImages() async throws {
        let session = LanguageModelSession(model: TestSupport.fastModel)
        let image = try #require(Self.solidImage(red: 0, green: 0, blue: 1))

        let response = try await session.respond {
            "What color is this image? Answer with one word."
            Attachment(image)
        }

        #expect(response.content.lowercased().contains("blue"))
    }

    @Test func reportsInvalidAPIKey() async throws {
        let session = LanguageModelSession(model: GrokModel.grok4_3.apiKey("xai-invalid"))

        await #expect {
            try await session.respond(to: "Hello")
        } throws: { error in
            guard case GrokError.requestFailed(let statusCode, _, _) = error else { return false }
            return statusCode == 400 || statusCode == 401 || statusCode == 403
        }
    }

    private static func solidImage(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage? {
        let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        context?.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return context?.makeImage()
    }
}

@Generable
struct CityFacts {
    @Guide(description: "The city's name")
    var name: String

    @Guide(description: "The country the city is in")
    var country: String

    @Guide(description: "The approximate population of the city", .minimum(0))
    var population: Int

    @Guide(description: "Famous landmarks in the city", .count(1...5))
    var landmarks: [String]
}

/// A type that declares its properties out of alphabetical order.
@Generable
struct TripPlan {
    @Guide(description: "A short, catchy title for the trip")
    var title: String

    @Guide(description: "The destination city")
    var destination: String

    @Guide(description: "The number of nights", .range(1...7))
    var nights: Int

    @Guide(description: "Planned activities", .count(3))
    var activities: [String]

    @Guide(description: "A one-sentence summary of the trip")
    var summary: String
}

final class WeatherTool: Tool {
    let name = "getWeather"
    let description = "Gets the current weather for a city."

    @Generable
    struct Arguments {
        @Guide(description: "The name of the city")
        var city: String
    }

    private let recordedCities = Mutex<[String]>([])

    var cities: [String] { recordedCities.withLock { $0 } }

    @concurrent func call(arguments: Arguments) async throws -> String {
        recordedCities.withLock { $0.append(arguments.city) }
        return "It's 23°C and sunny in \(arguments.city)."
    }
}
