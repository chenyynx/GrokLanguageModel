//
//  ContentView.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import GrokLanguageModel
import SwiftUI

/// The main window: a sidebar of demos next to the selected demo.
struct ContentView: View {
    @State private var selection: Demo? = Demo.initial

    // Each demo's state lives here so that it survives switching demos.
    @State private var chat = ChatModel()
    @State private var tripPlanner = TripPlannerModel()
    @State private var tools = ToolsModel()
    @State private var reasoning = ReasoningModel()
    @State private var vision = VisionModel()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Demos") {
                    ForEach(Demo.allCases) { demo in
                        NavigationLink(value: demo) {
                            DemoRow(demo: demo)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
            .safeAreaInset(edge: .bottom) {
                APIKeyStatusView()
                    .padding(10)
            }
        } detail: {
            detail(for: selection ?? .chat)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        ModelPicker()
                    }
                }
        }
    }

    @ViewBuilder
    private func detail(for demo: Demo) -> some View {
        switch demo {
        case .chat: ChatView(chat: chat)
        case .structuredOutput: TripPlannerView(planner: tripPlanner)
        case .tools: ToolsView(model: tools)
        case .reasoning: ReasoningView(model: reasoning)
        case .vision: VisionView(model: vision)
        }
    }
}

/// A sidebar row that describes a demo.
private struct DemoRow: View {
    let demo: Demo

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(demo.title)
                Text(demo.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: demo.systemImage)
        }
        .padding(.vertical, 3)
    }
}

/// The toolbar menu that picks the model that new requests use.
private struct ModelPicker: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Picker("Model", selection: $settings.selectedModel) {
            ForEach(GrokModel.presets, id: \.name) { model in
                Text(model.displayName).tag(model)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel("Model")
        .help("The Grok model that new requests use")
    }
}

/// A summary of where requests get their API key from.
private struct APIKeyStatusView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Settings")
            .help("Open Settings (⌘,)")
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
    }

    // `GrokConfiguration.apiKeySource` reports where the key comes from
    // without exposing the key itself.

    private var symbol: String {
        switch settings.apiKeySource {
        case .configuration: "key.fill"
        case .environment: "terminal.fill"
        case nil: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch settings.apiKeySource {
        case .configuration: .green
        case .environment: .blue
        case nil: .orange
        }
    }

    private var title: String {
        switch settings.apiKeySource {
        case .configuration: "API key in Keychain"
        case .environment(let variable): "Using \(variable)"
        case nil: "No API key"
        }
    }

    private var detail: String {
        switch settings.apiKeySource {
        case .configuration: "Set on GrokConfiguration.default"
        case .environment: "Read from the environment"
        case nil: "Add one in Settings (⌘,)"
        }
    }
}
