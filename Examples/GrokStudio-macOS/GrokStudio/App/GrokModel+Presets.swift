//
//  GrokModel+Presets.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import FoundationModels
import GrokLanguageModel

// GrokStudio's model pickers list `GrokModel.presets` and show each model's
// `displayName`, so a new preset appears in the app without any changes here.
extension GrokModel {
    /// The preset with the model identifier you specify, like `grok-4.7`, or
    /// `nil` if there isn't one.
    ///
    /// GrokStudio saves the default model by its identifier, which stays the
    /// same when the package adds presets.
    static func preset(named name: String) -> GrokModel? {
        presets.first { $0.name == name }
    }

    /// A short description of what makes the model different, like
    /// "500K context · adjustable reasoning".
    var summary: String {
        let context = contextSize >= 1_000_000
            ? "\(contextSize / 1_000_000)M context"
            : "\(contextSize / 1_000)K context"
        return "\(context) · \(reasoningSummary)"
    }

    /// How the model reasons, and whether a request can change it.
    var reasoningSummary: String {
        if !capabilities.contains(.reasoning) {
            "no reasoning"
        } else if supportsReasoningEffort {
            "adjustable reasoning"
        } else {
            "fixed reasoning"
        }
    }

    /// The reasoning efforts that the model accepts, like "low, medium, high".
    var supportedReasoningEffortsSummary: String {
        supportsReasoningEffort
            ? supportedReasoningEfforts.map(\.rawValue).joined(separator: ", ")
            : "not adjustable"
    }
}
