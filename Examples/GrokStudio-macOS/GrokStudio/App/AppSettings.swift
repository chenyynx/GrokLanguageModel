//
//  AppSettings.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import GrokLanguageModel
import Observation

/// App-wide settings: the xAI API key and the model that the demos use.
@Observable
final class AppSettings {
    /// The model that new requests use, which the toolbar's model picker changes.
    var selectedModel: GrokModel

    /// The model that the app selects when it launches.
    ///
    /// GrokStudio saves the model's identifier, like `grok-4.7`.
    var defaultModel: GrokModel {
        didSet {
            UserDefaults.standard.set(defaultModel.name, forKey: Self.defaultModelKey)
            selectedModel = defaultModel
        }
    }

    /// A Boolean value that indicates whether the Keychain holds an API key.
    private(set) var hasStoredAPIKey = false

    /// Where requests get their API key from, or `nil` if they don't send one.
    ///
    /// GrokStudio sets the key from the Keychain on `GrokConfiguration.default`,
    /// so `.configuration` means a saved key. Without one, GrokLanguageModel
    /// falls back to the `GROK_API_KEY` or `XAI_API_KEY` environment variable,
    /// but only for requests to an xAI host.
    private(set) var apiKeySource: GrokConfiguration.APIKeySource?

    /// A description of the last Keychain error, if the last operation failed.
    private(set) var keychainError: String?

    @ObservationIgnored private var hasConsumedDemoPrompt = false

    init() {
        let storedModel = UserDefaults.standard.string(forKey: Self.defaultModelKey).flatMap(GrokModel.preset(named:))
        defaultModel = storedModel ?? .grok4
        selectedModel = storedModel ?? .grok4
        loadAPIKey()
    }

    // MARK: API key

    /// Saves an API key to the Keychain and starts using it for requests.
    func saveAPIKey(_ key: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try KeychainStore.set(key, forAccount: Self.apiKeyAccount)
            apply(apiKey: key)
        } catch {
            keychainError = error.localizedDescription
        }
    }

    /// Removes the saved API key, so requests to the xAI API fall back to the
    /// environment.
    func removeAPIKey() {
        do {
            try KeychainStore.removeValue(forAccount: Self.apiKeyAccount)
            apply(apiKey: nil)
        } catch {
            keychainError = error.localizedDescription
        }
    }

    private func loadAPIKey() {
        do {
            apply(apiKey: try KeychainStore.string(forAccount: Self.apiKeyAccount))
        } catch {
            apply(apiKey: nil)
            keychainError = error.localizedDescription
        }
    }

    /// Configures every Grok model that doesn't have its own configuration.
    ///
    /// A `nil` key lets requests to the xAI API fall back to the
    /// `GROK_API_KEY` environment variable, which is handy when you run the
    /// app from Xcode.
    private func apply(apiKey: String?) {
        let apiKey = apiKey.flatMap { $0.isEmpty ? nil : $0 }
        GrokConfiguration.default.apiKey = apiKey
        hasStoredAPIKey = apiKey != nil
        apiKeySource = GrokConfiguration.default.apiKeySource
        keychainError = nil
    }

    private static let defaultModelKey = "defaultModel"
    private static let apiKeyAccount = "xai-api-key"

    // MARK: Screenshots

    /// Returns the `-demoPrompt` launch argument the first time it's called,
    /// so that the demo that opens at launch can run it once.
    func consumeDemoPrompt() -> String? {
        guard !hasConsumedDemoPrompt else { return nil }
        hasConsumedDemoPrompt = true
        guard let prompt = UserDefaults.standard.string(forKey: "demoPrompt"), !prompt.isEmpty else { return nil }
        return prompt
    }
}
