//
//  TripPlannerModel.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels
import GrokLanguageModel
import Observation

/// Generates a `TripPlan` and streams its partially generated fields.
@Observable
final class TripPlannerModel {
    var destination = "Kyoto, Japan"
    var days = 3
    var interests = "temples, food markets, and quiet gardens"

    /// The plan so far. Its properties are optional until Grok writes them.
    private(set) var plan: TripPlan.PartiallyGenerated?

    /// The generated content so far, as pretty-printed JSON.
    private(set) var json = ""

    private(set) var session: LanguageModelSession?
    private(set) var isGenerating = false
    var error: PresentableError?

    @ObservationIgnored private var task: Task<Void, Never>?

    var canGenerate: Bool {
        !destination.trimmingCharacters(in: .whitespaces).isEmpty && !isGenerating
    }

    func generate(using model: GrokModel) {
        stop()
        let session = LanguageModelSession(
            model: model,
            instructions: """
                You are an expert travel planner. Plan realistic, specific itineraries that name real \
                places, and estimate costs per person in US dollars.
                """
        )
        let prompt = "Plan a \(days)-day trip to \(destination) for a traveler who loves \(interests)."
        self.session = session
        plan = nil
        json = ""
        error = nil
        isGenerating = true

        task = Task {
            do {
                // Light reasoning keeps planning snappy; the Reasoning demo explores deeper levels.
                let stream = session.streamResponse(
                    to: prompt,
                    generating: TripPlan.self,
                    contextOptions: ContextOptions(reasoningLevel: .light)
                )
                for try await snapshot in stream {
                    // Don't let a canceled run overwrite the run that replaced it.
                    guard !Task.isCancelled else { break }
                    plan = snapshot.content
                    json = Self.prettyPrinted(snapshot.rawContent.jsonString)
                }
            } catch {
                if !Task.isCancelled && !(error is CancellationError) {
                    self.error = PresentableError(error)
                }
            }
            // A canceled run's state belongs to `stop()` or to the run that replaced it.
            if !Task.isCancelled {
                isGenerating = false
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isGenerating = false
    }

    private static func prettyPrinted(_ json: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes])
        else { return json }
        return String(decoding: data, as: UTF8.self)
    }
}
