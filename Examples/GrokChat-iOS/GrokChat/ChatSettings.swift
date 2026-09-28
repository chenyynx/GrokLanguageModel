//
//  ChatSettings.swift
//  GrokChat
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels
import GrokLanguageModel
import Observation

/// The choices that control how GrokChat talks to Grok.
///
/// The model, reasoning effort, and tool choices persist in `UserDefaults`. The
/// API key persists in the Keychain and is applied to
/// `GrokConfiguration.default`, which every Grok model uses unless it has its
/// own configuration.
@Observable
final class ChatSettings {
    /// The Grok model preset to chat with, one of `GrokModel.presets`.
    var preset: GrokModel {
        didSet {
            UserDefaults.standard.set(preset.name, forKey: Keys.model)
            if let reasoningEffort, !preset.supportedReasoningEfforts.contains(reasoningEffort) {
                self.reasoningEffort = nil
            }
        }
    }

    /// How much the model thinks before it replies, or `nil` to use the
    /// model's default effort.
    ///
    /// When this isn't `nil`, it's one of the preset's `supportedReasoningEfforts`.
    var reasoningEffort: GrokModel.ReasoningEffort? {
        didSet { UserDefaults.standard.set(reasoningEffort?.rawValue, forKey: Keys.reasoningEffort) }
    }

    /// Whether the model can call ``CurrentTimeTool``.
    var isTimeToolEnabled: Bool {
        didSet { UserDefaults.standard.set(isTimeToolEnabled, forKey: Keys.timeTool) }
    }

    /// Where the API key that requests send comes from, or `nil` if there's no key.
    ///
    /// The package resolves the key: a key saved in the Keychain, then, for
    /// requests to xAI, the `GROK_API_KEY` or `XAI_API_KEY` environment variable.
    private(set) var apiKeySource: GrokConfiguration.APIKeySource?

    init() {
        let defaults = UserDefaults.standard
        let savedName = defaults.string(forKey: Keys.model)
        let preset = GrokModel.presets.first { $0.name == savedName } ?? .grok4
        self.preset = preset
        // Ignore a saved effort that the saved model doesn't accept.
        let reasoningEffort = defaults.string(forKey: Keys.reasoningEffort).map(GrokModel.ReasoningEffort.init(rawValue:))
        if let reasoningEffort, preset.supportedReasoningEfforts.contains(reasoningEffort) {
            self.reasoningEffort = reasoningEffort
        } else {
            self.reasoningEffort = nil
        }
        isTimeToolEnabled = defaults.object(forKey: Keys.timeTool) as? Bool ?? true
        applySavedAPIKey()
    }

    /// The model to create sessions with, configured with the chosen reasoning effort.
    var model: GrokModel {
        preset.reasoningEffort(reasoningEffort)
    }

    /// Whether an API key is saved in the Keychain.
    ///
    /// GrokChat only sets `GrokConfiguration.default.apiKey` to a saved key,
    /// so a key from the configuration is the saved one.
    var hasSavedAPIKey: Bool {
        apiKeySource == .configuration
    }

    /// Saves an API key in the Keychain and starts using it.
    func saveAPIKey(_ apiKey: String) throws {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }
        try KeychainStore.set(apiKey, forAccount: Keys.apiKeyAccount)
        GrokConfiguration.default.apiKey = apiKey
        apiKeySource = GrokConfiguration.default.apiKeySource
    }

    /// Removes the saved API key, so that requests to xAI fall back to the environment.
    func removeAPIKey() throws {
        try KeychainStore.removeValue(forAccount: Keys.apiKeyAccount)
        GrokConfiguration.default.apiKey = nil
        apiKeySource = GrokConfiguration.default.apiKeySource
    }

    private func applySavedAPIKey() {
        // With no key here, requests to xAI fall back to the GROK_API_KEY and
        // XAI_API_KEY environment variables on their own.
        GrokConfiguration.default.apiKey = KeychainStore.string(forAccount: Keys.apiKeyAccount)
        apiKeySource = GrokConfiguration.default.apiKeySource
    }

    private enum Keys {
        static let model = "model"
        static let reasoningEffort = "reasoningEffort"
        static let timeTool = "timeToolEnabled"
        static let apiKeyAccount = "xai-api-key"
    }
}

// MARK: - Display text

extension GrokModel {
    /// A short description of the model's strengths and limits, from the
    /// preset's properties.
    var details: String {
        let context = "\(contextSize.formatted(.number.notation(.compactName))) context"
        let reasoning = if !capabilities.contains(.reasoning) {
            "no reasoning"
        } else if supportsReasoningEffort {
            "adjustable reasoning"
        } else {
            "fixed reasoning"
        }
        let facts = "\(context) · \(reasoning)"
        return name == GrokModel.grok4.name ? "Most capable · \(facts)" : facts
    }
}

extension GrokModel.ReasoningEffort {
    /// The name of the effort to show in Settings.
    var displayName: String {
        switch self {
        case .disabled: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Extra High"
        default: rawValue.capitalized
        }
    }
}
