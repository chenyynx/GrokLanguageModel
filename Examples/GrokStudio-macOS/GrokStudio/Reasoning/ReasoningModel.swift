//
//  ReasoningModel.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels
import GrokLanguageModel
import Observation

/// Asks a hard question at a reasoning level, and records how much each
/// level reasons.
@Observable
final class ReasoningModel {
    /// A reasoning level to choose from.
    ///
    /// The levels come from the selected model's supported reasoning efforts.
    /// Each effort becomes the standard level that maps to it, like `.light`
    /// for `low`, or a custom level, like `.custom("xhigh")`, which Grok
    /// models pass straight through as the effort.
    struct Level: Identifiable, Hashable {
        let reasoningLevel: ContextOptions.ReasoningLevel

        static let light = Level(reasoningLevel: .light)
        static let moderate = Level(reasoningLevel: .moderate)
        static let deep = Level(reasoningLevel: .deep)

        /// The levels that the Foundation Models framework defines.
        static let standard = [light, moderate, deep]

        /// The levels to offer for a model, from least to most reasoning.
        ///
        /// Each reasoning effort that the model supports becomes a standard
        /// level when one maps to it, or a custom level otherwise. A model
        /// that doesn't accept a reasoning effort offers the standard levels,
        /// which requests don't send.
        static func levels(for model: GrokModel) -> [Level] {
            guard model.supportsReasoningEffort else { return standard }
            return model.supportedReasoningEfforts.map { effort in
                standard.first { $0.effort == effort } ?? Level(reasoningLevel: .custom(effort.rawValue))
            }
        }

        /// The `reasoning.effort` that the level becomes in a request.
        var effort: GrokModel.ReasoningEffort {
            GrokModel.ReasoningEffort(reasoningLevel)
        }

        var id: String { code }

        var title: String {
            switch reasoningLevel {
            case .light: "Light"
            case .moderate: "Moderate"
            case .deep: "Deep"
            case .custom(let effort): effort
            @unknown default: effort.rawValue
            }
        }

        /// The Swift code that requests the level, like `.custom("xhigh")`.
        var code: String {
            ".\(reasoningLevel.displayName)"
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(code)
        }
    }

    /// A finished run, for comparing levels.
    struct Run: Identifiable {
        let id = UUID()
        var modelName: String
        var level: Level
        var reasoningTokens: Int
        var outputTokens: Int
        var duration: Duration
    }

    static let sampleQuestions = [
        "Alice, Bob, and Carol each either always lie or always tell the truth. Alice says \"Bob is a liar.\" Bob says \"Carol is a liar.\" Carol says \"Alice and Bob are both liars.\" Who tells the truth?",
        "What's the smallest positive integer that leaves a remainder of 1 when divided by 2, 3, 4, 5, or 6, and is divisible by 7?",
        "How many positive integers less than 1,000 are divisible by 7 but not by 11?",
        "A snail climbs 3 m up a 20 m well each day and slips back 2 m each night. On which day does it reach the top?",
    ]

    var question = sampleQuestions[0]
    var level = Level.moderate
    private(set) var session: LanguageModelSession?
    private(set) var answer = ""
    private(set) var isResponding = false
    private(set) var startDate: Date?
    private(set) var duration: Duration?
    private(set) var runs: [Run] = []
    var error: PresentableError?

    @ObservationIgnored private var task: Task<Void, Never>?

    /// The reasoning summary so far, from the transcript's reasoning entries.
    ///
    /// The session's transcript is observable, so the summary streams in
    /// while the model thinks, before the answer starts.
    var reasoningSummary: String {
        reasoningEntries
            .map(\.segments.plainText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// A Boolean value that indicates whether the transcript holds encrypted
    /// reasoning, which Grok models send back to the same model on the next turn.
    var hasEncryptedReasoning: Bool {
        reasoningEntries.contains { $0.signature != nil }
    }

    private var reasoningEntries: [Transcript.Reasoning] {
        session?.transcript.compactMap { entry in
            if case .reasoning(let reasoning) = entry { reasoning } else { nil }
        } ?? []
    }

    /// Chooses a level that the model offers, if it doesn't offer the current one.
    func chooseSupportedLevel(for model: GrokModel) {
        if !Level.levels(for: model).contains(level) {
            level = .moderate
        }
    }

    func run(using model: GrokModel) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        stop()

        let session = LanguageModelSession(
            model: model,
            instructions: "Answer concisely and explain the key steps. Write math as plain text, not LaTeX, and use × for multiplication."
        )
        let level = level
        let contextOptions = ContextOptions(reasoningLevel: level.reasoningLevel)
        self.session = session
        answer = ""
        error = nil
        duration = nil
        startDate = .now
        isResponding = true

        task = Task {
            let start = ContinuousClock.now
            do {
                for try await snapshot in session.streamResponse(to: question, contextOptions: contextOptions) {
                    guard !Task.isCancelled else { break }
                    answer = snapshot.content
                }
                // Only a run that finished belongs in the history.
                guard !Task.isCancelled else { return }
                let duration = ContinuousClock.now - start
                self.duration = duration
                runs.insert(Run(
                    modelName: model.displayName,
                    level: level,
                    reasoningTokens: session.usage.output.reasoningTokenCount,
                    outputTokens: session.usage.output.totalTokenCount,
                    duration: duration
                ), at: 0)
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
