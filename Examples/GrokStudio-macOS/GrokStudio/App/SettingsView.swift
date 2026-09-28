//
//  SettingsView.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import GrokLanguageModel
import SwiftUI

/// The Settings window, where you add an API key and choose a default model.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var draftKey = ""

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                SecureField("API key", text: $draftKey, prompt: Text(verbatim: "xai-…"))
                    .onSubmit(saveKey)
                HStack {
                    keyStatus
                    Spacer()
                    if settings.hasStoredAPIKey {
                        Button("Remove", role: .destructive) {
                            settings.removeAPIKey()
                        }
                    }
                    Button("Save", action: saveKey)
                        .keyboardShortcut(.defaultAction)
                        .disabled(trimmedKey.isEmpty)
                }
                if let error = settings.keychainError {
                    Label(error, systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            } header: {
                Text("xAI API Key")
            } footer: {
                Text("GrokStudio keeps your key in the Keychain and sets it on `GrokConfiguration.default`. Without a key, requests to the xAI API fall back to the `GROK_API_KEY` or `XAI_API_KEY` environment variable, which GrokLanguageModel never sends to other hosts. [Get a key from the xAI Console](https://console.x.ai).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Models") {
                Picker("Default model", selection: $settings.defaultModel) {
                    ForEach(GrokModel.presets, id: \.name) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                LabeledContent("Identifier") {
                    Text(settings.defaultModel.name)
                        .monospaced()
                        .textSelection(.enabled)
                }
                LabeledContent("Capabilities", value: settings.defaultModel.summary)
                LabeledContent("Reasoning efforts", value: settings.defaultModel.supportedReasoningEffortsSummary)
            }

            Section("Shipping to Production") {
                Label {
                    Text("An API key that ships inside an app can be extracted from it. In production, point `baseURL` at your own server, which adds the key and forwards requests to the xAI API. Grok models don't require a key, or read one from the environment, when `baseURL` isn't an xAI host.")
                } icon: {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.tint)
                }
                Text(verbatim: #"GrokConfiguration.default.baseURL = URL(string: "https://api.example.com/grok/v1")!"#)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 590)
    }

    private var trimmedKey: String {
        draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var keyStatus: some View {
        switch settings.apiKeySource {
        case .configuration:
            Label("Saved in the Keychain", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .environment(let variable):
            Label("Using the \(variable) environment variable", systemImage: "terminal")
                .foregroundStyle(.secondary)
        case nil:
            Label("No key configured", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func saveKey() {
        guard !trimmedKey.isEmpty else { return }
        settings.saveAPIKey(trimmedKey)
        if settings.keychainError == nil {
            draftKey = ""
        }
    }
}
