//
//  ToolsView.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import SwiftUI

/// The Tools demo: Grok calls a weather tool and a calculator, and a live
/// log shows each call's arguments and output.
struct ToolsView: View {
    @Bindable var model: ToolsModel
    @Environment(AppSettings.self) private var settings
    @AppStorage("showsToolsTranscript") private var showsTranscript = false

    var body: some View {
        // The log sits next to the prompt, or below it when the window is narrow.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                // Explicit widths keep the scroll view from claiming the width
                // of the prompt on one line.
                mainColumn
                    .frame(minWidth: 300, idealWidth: 300, maxWidth: .infinity)
                Divider()
                toolLog
                    .frame(minWidth: 260, idealWidth: 260, maxWidth: 380, maxHeight: .infinity)
            }
            VStack(spacing: 0) {
                mainColumn
                    .frame(minWidth: 0, maxWidth: .infinity)
                Divider()
                toolLog
                    .frame(height: 220)
            }
        }
        .errorBanner($model.error)
        .navigationTitle("Tools")
        .navigationSubtitle("getWeather · calculate")
        .transcriptInspector(for: model.session, isResponding: model.isResponding, isPresented: $showsTranscript)
        .task {
            // Screenshot hook: `-demo tools -demoPrompt "…"` runs a prompt once at launch.
            if let prompt = settings.consumeDemoPrompt() {
                model.prompt = prompt
                model.run(using: settings.selectedModel)
            }
        }
    }

    private var mainColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                promptSection
                answerSection
                availableTools
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var toolLog: some View {
        ToolLog(invocations: model.invocations, isResponding: model.isResponding)
    }

    // MARK: Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Prompt")
                    .font(.headline)
                Spacer()
                Menu("Examples") {
                    ForEach(ToolsModel.samplePrompts, id: \.self) { prompt in
                        Button(prompt) { model.prompt = prompt }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            TextField("Ask something that needs the weather or some math", text: $model.prompt, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.run(using: settings.selectedModel) }

            // Put the Run button below the picker, and then drop the picker's
            // label, as the column gets narrower.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    callingModePicker
                    Spacer()
                    runButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    callingModePicker
                    runButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    callingModePicker
                        .labelsHidden()
                    runButton
                }
            }
            Text(model.callingMode.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var callingModePicker: some View {
        Picker("Tool calling", selection: $model.callingMode) {
            ForEach(ToolsModel.CallingMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    @ViewBuilder
    private var runButton: some View {
        if model.isResponding {
            Button("Stop", systemImage: "stop.fill", role: .cancel) {
                model.stop()
            }
            .keyboardShortcut(".", modifiers: .command)
            .help("Stop responding (⌘.)")
        } else {
            Button("Run", systemImage: "play.fill") {
                model.run(using: settings.selectedModel)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Run the prompt (⌘Return)")
            .disabled(model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: Answer

    @ViewBuilder
    private var answerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Answer")
                .font(.headline)
            Group {
                if !model.answer.isEmpty {
                    MarkdownText(model.answer)
                } else if model.isResponding {
                    TypingIndicator()
                } else {
                    Text("Run the prompt to see Grok's answer. Its tool calls appear in the log.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
        }
    }

    // MARK: Tool definitions

    private var availableTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Available Tools")
                .font(.headline)
            ForEach(ToolsModel.toolSummaries) { tool in
                ToolDefinitionView(tool: tool)
            }
        }
    }
}

/// A tool's name, description, and the parameter schema that `@Generable` produced.
private struct ToolDefinitionView: View {
    let tool: ToolSummary
    @State private var showsSchema = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(tool.name)
                    .font(.body.monospaced().weight(.semibold))
            } icon: {
                Image(systemName: ToolLog.symbol(for: tool.name))
                    .foregroundStyle(.tint)
            }
            Text(tool.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Parameters schema", isExpanded: $showsSchema) {
                Text(tool.parametersJSON)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
            }
            .font(.caption)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary)
        }
    }
}

/// A live log of tool invocations, grouped by the request that made them.
private struct ToolLog: View {
    let invocations: [ToolInvocation]
    let isResponding: Bool

    static func symbol(for toolName: String) -> String {
        switch toolName {
        case "getWeather": "cloud.sun"
        case "calculate": "function"
        default: "wrench.and.screwdriver"
        }
    }

    var body: some View {
        Group {
            if invocations.isEmpty {
                ContentUnavailableView(
                    "No Tool Calls",
                    systemImage: "wrench.and.screwdriver",
                    description: Text(isResponding ? "Waiting for Grok to call a tool…" : "Tool calls appear here as the session makes them.")
                )
            } else {
                List {
                    ForEach(rounds, id: \.self) { round in
                        let calls = invocations.filter { $0.round == round }
                        Section {
                            ForEach(calls) { invocation in
                                row(for: invocation)
                            }
                        } header: {
                            Text(calls.count > 1 ? "Round \(round) · \(calls.count) parallel calls" : "Round \(round)")
                        }
                    }
                }
                .listStyle(.inset)
                .animation(.snappy, value: invocations.count)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Label("Tool Log", systemImage: "list.bullet.rectangle.portrait")
                    .font(.headline)
                Spacer()
                Text("^[\(invocations.count) call](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.bar)
        }
    }

    private var rounds: [Int] {
        Array(Set(invocations.map(\.round))).sorted()
    }

    private func row(for invocation: ToolInvocation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(invocation.toolName, systemImage: Self.symbol(for: invocation.toolName))
                    .font(.callout.monospaced().weight(.semibold))
                Spacer()
                if invocation.output != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Finished")
                } else if isResponding {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Running")
                }
            }
            detail("Arguments", invocation.arguments)
            if let output = invocation.output {
                detail("Output", output)
            }
        }
        .padding(.vertical, 4)
    }

    private func detail(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
