//
//  MessageView.swift
//  GrokChat
//
//  Created by Marcus Arnett on 9/28/26.
//

import FoundationModels
import SwiftUI
import UIKit

/// A message in the conversation.
struct MessageView: View {
    var message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            UserMessageView(message: message)
        case .assistant:
            ReplyView(message: message)
        }
    }
}

// MARK: - User messages

private struct UserMessageView: View {
    var message: ChatMessage

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let image = message.image {
                Image(image, scale: 1, label: Text("Attached photo"))
                    .resizable()
                    .scaledToFill()
                    .frame(width: 200, height: 200)
                    .clipShape(.rect(cornerRadius: 20))
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(.tint, in: .rect(cornerRadius: 20))
                    .contextMenu {
                        CopyButton(text: message.text)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
    }
}

// MARK: - Replies

private struct ReplyView: View {
    var message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.reasoning.isEmpty {
                ThoughtProcessView(reasoning: message.reasoning)
            }
            if !message.toolCalls.isEmpty {
                ToolCallChips(toolNames: message.toolCalls)
            }

            // Snapshots arrive as the text streams in, so the bubble grows
            // word by word. Until the first words arrive, show that Grok is
            // working on the reply.
            if !message.text.isEmpty {
                MarkdownText(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.fill.quinary, in: .rect(cornerRadius: 20))
                    .contextMenu {
                        CopyButton(text: message.text)
                    }
            } else if message.isStreaming {
                TypingIndicator()
            }

            if message.wasStopped {
                Label("Stopped", systemImage: "stop.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !message.isStreaming, let usage = message.usage, usage.totalTokenCount > 0 {
                UsageView(usage: usage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 32)
        .animation(.default, value: message.isStreaming)
    }
}

/// A collapsible summary of the model's reasoning, from the reasoning entries
/// in the response's transcript.
private struct ThoughtProcessView: View {
    var reasoning: String

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            MarkdownText(reasoning)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(width: 3)
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } label: {
            Label("Thought process", systemImage: "brain")
        }
        .disclosureGroupStyle(CompactDisclosureStyle())
    }
}

/// A disclosure group style with a small chevron right after the label.
private struct CompactDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    configuration.label
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")

            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity)
            }
        }
    }
}

/// Chips that show which tools the model called, from the tool call entries in
/// the response's transcript.
private struct ToolCallChips: View {
    var toolNames: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(uniqueNames, id: \.self) { name in
                let count = toolNames.count { $0 == name }
                Label(count > 1 ? "Used tool: \(name) ×\(count)" : "Used tool: \(name)", systemImage: "wrench.and.screwdriver.fill")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(.tint)
                    .background(.tint.opacity(0.12), in: .capsule)
            }
        }
    }

    private var uniqueNames: [String] {
        toolNames.reduce(into: []) { names, name in
            if !names.contains(name) { names.append(name) }
        }
    }
}

/// An animated placeholder for a reply whose text hasn't started streaming yet,
/// while the model reasons or calls tools.
private struct TypingIndicator: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "ellipsis")
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
            Text("Thinking")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.fill.quinary, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

/// The tokens that a reply used.
private struct UsageView: View {
    var usage: LanguageModelSession.Usage

    var body: some View {
        Text(summary)
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .padding(.leading, 4)
    }

    private var summary: String {
        var parts = ["Tokens: \(usage.input.totalTokenCount.formatted()) in"]
        if usage.input.cachedTokenCount > 0 {
            parts.append("\(usage.input.cachedTokenCount.formatted()) cached")
        }
        parts.append("\(usage.output.totalTokenCount.formatted()) out")
        if usage.output.reasoningTokenCount > 0 {
            parts.append("\(usage.output.reasoningTokenCount.formatted()) reasoning")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Shared

/// Text that renders inline Markdown, like bold, italics, code, and links.
private struct MarkdownText: View {
    var markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    var body: some View {
        Text(attributedString)
    }

    private var attributedString: AttributedString {
        // Inline-only parsing keeps line breaks but ignores block syntax, so
        // show list markers as bullets.
        let text = markdown.replacing(#/^([ \t]*)[-*+] /#.anchorsMatchLineEndings()) { "\($0.1)• " }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct CopyButton: View {
    var text: String

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = text
        }
    }
}
