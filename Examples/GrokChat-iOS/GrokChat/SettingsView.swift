//
//  SettingsView.swift
//  GrokChat
//
//  Created by Marcus Arnett on 9/28/26.
//

import GrokLanguageModel
import SwiftUI

/// A sheet for the API key, model, reasoning effort, and tools.
struct SettingsView: View {
    @Environment(ChatSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyDraft = ""
    @State private var keychainError: String?

    private static let consoleURL = URL(string: "https://console.x.ai")!
    private static let repositoryURL = URL(string: "https://github.com/MarcoDotIO/GrokLanguageModel")!

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                apiKeySection

                Section {
                    Picker("Model", selection: $settings.preset) {
                        ForEach(GrokModel.presets, id: \.name) { preset in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.displayName)
                                Text(preset.details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(preset)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Model")
                }

                Section {
                    if settings.preset.supportsReasoningEffort {
                        Picker("Reasoning Effort", selection: $settings.reasoningEffort) {
                            Text("Default").tag(GrokModel.ReasoningEffort?.none)
                            ForEach(settings.preset.supportedReasoningEfforts, id: \.self) { effort in
                                Text(effort.displayName).tag(Optional(effort))
                            }
                        }
                    } else {
                        LabeledContent("Reasoning Effort", value: "Not Adjustable")
                    }
                } header: {
                    Text("Reasoning")
                } footer: {
                    Text("Higher effort thinks longer before answering. Tap **Thought process** above a reply to read a summary of the model's reasoning.")
                }

                Section {
                    Toggle(isOn: $settings.isTimeToolEnabled) {
                        Label("Current Time", systemImage: "clock")
                    }
                } header: {
                    Text("Tools")
                } footer: {
                    Text("Lets Grok call `CurrentTimeTool`, a Foundation Models `Tool`, to look up the date and time on this device. Settings changes apply to your next message, and the conversation carries over.")
                }

                Section {
                    Link(destination: Self.repositoryURL) {
                        LabeledContent("GrokLanguageModel", value: "GitHub")
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Keychain Error", isPresented: isShowingKeychainError, presenting: keychainError) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
        }
    }

    private var apiKeySection: some View {
        Section {
            let status = apiKeyStatus
            Label {
                Text(status.title)
            } icon: {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status.color)
            }

            SecureField("Paste your xAI API key", text: $apiKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(saveAPIKey)

            Button(settings.hasSavedAPIKey ? "Replace Saved Key" : "Save to Keychain", action: saveAPIKey)
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if settings.hasSavedAPIKey {
                Button("Remove Saved Key", role: .destructive, action: removeAPIKey)
            }
        } header: {
            Text("xAI API Key")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Without a saved key, requests to xAI use the `GROK_API_KEY` or `XAI_API_KEY` environment variable, which you can set in an unshared copy of the scheme while you develop. The package never sends those variables to a custom `baseURL`.")
                Text("**Don't ship API keys in apps** — anyone can extract them. In production, set `GrokConfiguration.default.baseURL` to your own proxy server, which adds the key before forwarding requests to xAI.")
                Link("Get an API key at console.x.ai", destination: Self.consoleURL)
            }
        }
    }

    /// A description of the key that requests use, from the package's
    /// `GrokConfiguration.APIKeySource`.
    private var apiKeyStatus: (title: String, systemImage: String, color: Color) {
        switch settings.apiKeySource {
        case .configuration:
            ("Using the key saved in the Keychain", "checkmark.seal.fill", .green)
        case .environment(let variable):
            ("Using \(variable) from the environment", "terminal.fill", .blue)
        case nil:
            ("No API key set", "exclamationmark.circle.fill", .orange)
        }
    }

    private var isShowingKeychainError: Binding<Bool> {
        Binding {
            keychainError != nil
        } set: { isPresented in
            if !isPresented { keychainError = nil }
        }
    }

    private func saveAPIKey() {
        do {
            try settings.saveAPIKey(apiKeyDraft)
            apiKeyDraft = ""
        } catch {
            keychainError = error.localizedDescription
        }
    }

    private func removeAPIKey() {
        do {
            try settings.removeAPIKey()
        } catch {
            keychainError = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
        .environment(ChatSettings())
}
