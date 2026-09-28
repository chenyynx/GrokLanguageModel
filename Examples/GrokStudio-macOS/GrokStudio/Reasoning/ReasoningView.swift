//
//  ReasoningView.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import FoundationModels
import GrokLanguageModel
import SwiftUI

/// The Reasoning demo: choose a `ContextOptions` reasoning level, then
/// compare Grok's reasoning summary with its answer.
struct ReasoningView: View {
    @Bindable var model: ReasoningModel
    @Environment(AppSettings.self) private var settings
    @AppStorage("showsReasoningTranscript") private var showsTranscript = false

    var body: some View {
        VStack(spacing: 16) {
            controls
            HStack(alignment: .top, spacing: 16) {
                reasoningPane
                answerPane
            }
            .frame(maxHeight: .infinity)
            statistics
            if !model.runs.isEmpty {
                history
            }
        }
        .padding(20)
        .errorBanner($model.error)
        .navigationTitle("Reasoning")
        .navigationSubtitle("ContextOptions(reasoningLevel: \(model.level.code))")
        .transcriptInspector(for: model.session, isResponding: model.isResponding, isPresented: $showsTranscript)
        .onChange(of: settings.selectedModel, initial: true) { _, newModel in
            model.chooseSupportedLevel(for: newModel)
        }
        .task {
            // Screenshot hook: `-demo reasoning -demoPrompt "…"` asks a question once at launch.
            if let question = settings.consumeDemoPrompt() {
                model.question = question
                model.run(using: settings.selectedModel)
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                TextField("Ask a hard question", text: $model.question, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.run(using: settings.selectedModel) }
                Menu("Examples") {
                    ForEach(ReasoningModel.sampleQuestions, id: \.self) { question in
                        Button(question) { model.question = question }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            // Put the effort and the Think button on their own row, and then
            // drop the picker's label, as the window gets narrower.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    levelPicker
                    effortLabel
                    Spacer()
                    thinkButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    levelPicker
                    effortAndThinkButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    levelPicker
                        .labelsHidden()
                    effortAndThinkButton
                }
            }
            if let note = modelNote {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var levelPicker: some View {
        // The selected model's supported reasoning efforts decide the levels.
        Picker("Reasoning level", selection: $model.level) {
            ForEach(ReasoningModel.Level.levels(for: settings.selectedModel)) { level in
                Text(level.title).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private var effortLabel: some View {
        Text(settings.selectedModel.supportsReasoningEffort ? "reasoning.effort: \"\(model.level.effort.rawValue)\"" : "reasoning.effort: not sent")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private var effortAndThinkButton: some View {
        HStack(spacing: 12) {
            effortLabel
            Spacer()
            thinkButton
        }
    }

    @ViewBuilder
    private var thinkButton: some View {
        if model.isResponding {
            Button("Stop", systemImage: "stop.fill", role: .cancel) {
                model.stop()
            }
            .keyboardShortcut(".", modifiers: .command)
            .help("Stop thinking (⌘.)")
        } else {
            Button("Think", systemImage: "brain") {
                model.run(using: settings.selectedModel)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Ask the question (⌘Return)")
            .disabled(model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// Explains how the selected model treats the reasoning level.
    private var modelNote: String? {
        let grok = settings.selectedModel
        if !grok.capabilities.contains(.reasoning) {
            return "\(grok.displayName) doesn't reason. Choose a reasoning model from the toolbar."
        }
        if !grok.supportsReasoningEffort {
            return "\(grok.displayName) reasons at a fixed effort, so GrokLanguageModel doesn't send the level."
        }
        if model.level.effort == .disabled {
            return "The \"\(GrokModel.ReasoningEffort.disabled.rawValue)\" effort turns off \(grok.displayName)'s reasoning."
        }
        return nil
    }

    // MARK: Panes

    private var reasoningPane: some View {
        Pane(title: "Reasoning Summary", systemImage: "brain", tint: .purple) {
            if model.isResponding, let start = model.startDate {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else if let duration = model.duration {
                Text("Thought for \(duration.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1))))")
                    .foregroundStyle(.secondary)
            }
        } content: {
            let summary = model.reasoningSummary
            if !summary.isEmpty {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else if model.isResponding {
                TypingIndicator()
            } else if model.hasEncryptedReasoning {
                Text("Grok didn't return a summary this time. Its encrypted reasoning is still in the transcript, and Grok models send it back on the next turn.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Grok's reasoning summary streams in here from the transcript's `.reasoning` entries.")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var answerPane: some View {
        Pane(title: "Answer", systemImage: "sparkles", tint: .accentColor) {
            EmptyView()
        } content: {
            if !model.answer.isEmpty {
                MarkdownText(model.answer)
            } else if model.isResponding {
                Text("Waiting for Grok to finish thinking…")
                    .foregroundStyle(.tertiary)
            } else {
                Text("The answer appears here.")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Statistics

    private var statistics: some View {
        let usage = model.session?.usage
        let reasoning = StatTile(title: "Reasoning tokens", value: usage?.output.reasoningTokenCount, systemImage: "brain", tint: .purple)
        let output = StatTile(title: "Output tokens", value: usage?.output.totalTokenCount, systemImage: "arrow.up.circle", tint: .blue)
        let input = StatTile(title: "Input tokens", value: usage?.input.totalTokenCount, systemImage: "arrow.down.circle", tint: .teal)
        let share = StatTile(title: "Reasoning share", text: reasoningShare(usage), systemImage: "chart.pie", tint: .orange)
        // Four tiles in a row, or two rows of two when the window is narrow.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                reasoning
                output
                input
                share
            }
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    reasoning
                    output
                }
                GridRow {
                    input
                    share
                }
            }
        }
    }

    private func reasoningShare(_ usage: LanguageModelSession.Usage?) -> String? {
        guard let usage, usage.output.totalTokenCount > 0 else { return nil }
        let share = Double(usage.output.reasoningTokenCount) / Double(usage.output.totalTokenCount)
        return share.formatted(.percent.precision(.fractionLength(0)))
    }

    private var history: some View {
        Table(model.runs) {
            TableColumn("Model", value: \.modelName)
            TableColumn("Level") { run in
                Text(run.level.title)
            }
            TableColumn("Reasoning Tokens") { run in
                Text(run.reasoningTokens, format: .number)
                    .monospacedDigit()
            }
            TableColumn("Output Tokens") { run in
                Text(run.outputTokens, format: .number)
                    .monospacedDigit()
            }
            TableColumn("Time") { run in
                Text(run.duration.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1))))
                    .monospacedDigit()
            }
        }
        .frame(height: 140)
        .clipShape(.rect(cornerRadius: 10))
    }
}

/// A titled, scrolling pane.
private struct Pane<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                Spacer()
                accessory
                    .font(.caption)
            }
            .padding(12)
            Divider()
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
    }
}

/// A labeled number or value.
private struct StatTile: View {
    let title: String
    var text: String?
    let systemImage: String
    let tint: Color

    init(title: String, value: Int?, systemImage: String, tint: Color) {
        self.title = title
        self.text = value?.formatted()
        self.systemImage = systemImage
        self.tint = tint
    }

    init(title: String, text: String?, systemImage: String, tint: Color) {
        self.title = title
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(tint)
            Text(text ?? "—")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
        .animation(.smooth, value: text)
    }
}
