//
//  ToolsModel.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels
import GrokLanguageModel
import Observation

/// A tool call and its output, read from a session's transcript.
struct ToolInvocation: Identifiable {
    let id: String
    /// The request that made the call. Calls in the same round ran in parallel.
    let round: Int
    let toolName: String
    let arguments: String
    var output: String?
}

/// A tool definition, described for display.
struct ToolSummary: Identifiable {
    let name: String
    let description: String
    let parametersJSON: String
    var id: String { name }
}

/// Runs a prompt with tools and logs every tool invocation.
@Observable
final class ToolsModel {
    /// The ways the demo lets Grok call tools.
    enum CallingMode: String, CaseIterable, Identifiable {
        case allowed
        case requiredFirst
        case disallowed

        var id: Self { self }

        var title: String {
            switch self {
            case .allowed: "Allowed"
            case .requiredFirst: "Required First"
            case .disallowed: "Disallowed"
            }
        }

        var explanation: String {
            switch self {
            case .allowed:
                "Grok decides whether to call tools (tool_choice: auto)."
            case .requiredFirst:
                "Grok must call a tool before it answers (tool_choice: required). After the first call, a DynamicProfile allows Grok to answer."
            case .disallowed:
                "Grok answers without calling tools. The session leaves them out of the request."
            }
        }
    }

    static let samplePrompts = [
        "What's the weather in Tokyo and Reykjavík right now? How many degrees Fahrenheit warmer is Tokyo?",
        "If I invest $2,500 at 4.2% interest compounded monthly, what will I have after 10 years?",
        "Is it warmer in Cairo or in Cape Town? Convert both temperatures to Fahrenheit.",
        "What's the hypotenuse of a right triangle with legs of 7 and 24?",
    ]

    var prompt = samplePrompts[0]

    /// The tool calling mode, which the demo remembers between launches.
    var callingMode = UserDefaults.standard.string(forKey: ToolsModel.callingModeKey).flatMap(CallingMode.init(rawValue:)) ?? .allowed {
        didSet { UserDefaults.standard.set(callingMode.rawValue, forKey: Self.callingModeKey) }
    }

    private(set) var session: LanguageModelSession?
    private(set) var answer = ""
    private(set) var isResponding = false
    var error: PresentableError?

    @ObservationIgnored private var task: Task<Void, Never>?

    private static let callingModeKey = "toolCallingMode"

    /// The tools that every session in the demo can call.
    static let tools: [any Tool] = [WeatherTool(), CalculatorTool()]

    /// The instructions that sessions start with when Grok can call tools.
    static let instructions = """
        You're a helpful assistant with weather and calculator tools. Use getWeather for weather, \
        and use calculate for every calculation. Call independent tools in parallel. \
        Answer concisely and show the key numbers.
        """

    /// The instructions that sessions start with when tool calling is disallowed.
    ///
    /// The session leaves the tools out of the request, so instructions that
    /// mention them would lead Grok to write fake tool calls as its answer.
    static let instructionsWithoutTools = """
        You're a helpful assistant, but you can't call tools or look up live data right now, \
        so never write tool calls or promise to fetch anything. If a question needs live data, \
        like the current weather, say briefly that you can't check it. Do any math yourself. \
        Answer concisely and show the key numbers.
        """

    /// The tools' names, descriptions, and parameter schemas.
    static let toolSummaries: [ToolSummary] = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return tools.map { tool in
            let json = (try? encoder.encode(tool.parameters)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            return ToolSummary(name: tool.name, description: tool.description, parametersJSON: json)
        }
    }()

    /// The tool calls in the transcript, each paired with its output once it's available.
    ///
    /// The session's transcript is observable, so the log updates while the
    /// session calls tools.
    var invocations: [ToolInvocation] {
        guard let session else { return [] }
        var invocations: [ToolInvocation] = []
        var round = 0
        for entry in session.transcript {
            switch entry {
            case .toolCalls(let calls):
                round += 1
                for call in calls {
                    invocations.append(ToolInvocation(
                        id: call.id,
                        round: round,
                        toolName: call.toolName,
                        arguments: call.arguments.jsonString
                    ))
                }
            case .toolOutput(let output):
                if let index = invocations.lastIndex(where: { $0.id == output.id }) {
                    invocations[index].output = output.segments.plainText
                }
            default:
                break
            }
        }
        return invocations
    }

    func run(using model: GrokModel) {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        stop()

        let session: LanguageModelSession
        let options: GenerationOptions
        switch callingMode {
        case .allowed:
            session = LanguageModelSession(model: model, tools: Self.tools, instructions: Self.instructions)
            options = GenerationOptions(toolCallingMode: .allowed)
        case .requiredFirst:
            // `GenerationOptions(toolCallingMode: .required)` would require a
            // tool call on every request, so Grok would never answer. The
            // profile requires one only until the session makes one.
            session = LanguageModelSession(
                profile: ToolFirstProfile(model: model, instructions: Self.instructions, tools: Self.tools)
            )
            options = GenerationOptions()
        case .disallowed:
            session = LanguageModelSession(model: model, tools: Self.tools, instructions: Self.instructionsWithoutTools)
            options = GenerationOptions(toolCallingMode: .disallowed)
        }
        self.session = session
        answer = ""
        error = nil
        isResponding = true

        task = Task {
            do {
                for try await snapshot in session.streamResponse(to: prompt, options: options) {
                    guard !Task.isCancelled else { break }
                    answer = snapshot.content
                }
            } catch {
                if !Task.isCancelled && !(error is CancellationError) {
                    self.error = PresentableError(error)
                }
            }
            if !Task.isCancelled {
                isResponding = false
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isResponding = false
    }
}

// MARK: - Requiring a tool call first

// Sessions read their properties off the main actor, so the property is `nonisolated`.
nonisolated extension SessionPropertyValues {
    /// The number of tool calls that the session has made.
    @SessionPropertyEntry
    var toolCallCount: Int = 0
}

/// A dynamic profile that requires Grok to call a tool before it answers.
///
/// With `GenerationOptions(toolCallingMode: .required)`, every request that a
/// response makes requires a tool call, so Grok never writes a final answer.
/// This profile requires a tool call only until the session makes one. Each
/// call increments the `toolCallCount` session property, and from then on the
/// profile allows Grok to call more tools or answer.
///
/// Unlike the tools, the profile isn't `nonisolated`, because a `nonisolated`
/// type can't have the mutable storage that `@SessionProperty` adds.
struct ToolFirstProfile: LanguageModelSession.DynamicProfile {
    var model: GrokModel
    var instructions: String
    var tools: [any Tool]

    @SessionProperty(\.toolCallCount)
    var toolCallCount

    var body: some DynamicProfile {
        Profile {
            Instructions(instructions)
            tools
        }
        .model(model)
        .toolCallingMode(toolCallCount < 1 ? .required : .allowed)
        .onToolCall {
            toolCallCount += 1
        }
    }
}
