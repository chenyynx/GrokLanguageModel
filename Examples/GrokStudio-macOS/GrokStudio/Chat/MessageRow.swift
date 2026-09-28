//
//  MessageRow.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import AppKit
import SwiftUI

/// A chat message: a bubble for the user, Markdown for Grok, or a notice.
struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 80)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(.tint, in: .rect(cornerRadius: 18))
                    .accessibilityLabel("You: \(message.text)")
            }
        case .assistant:
            HStack(alignment: .top, spacing: 12) {
                GrokAvatar()
                VStack(alignment: .leading, spacing: 6) {
                    if message.text.isEmpty && message.isStreaming {
                        TypingIndicator()
                    } else {
                        MarkdownText(message.text)
                    }
                    if message.wasStopped {
                        Label("Stopped", systemImage: "stop.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 3)
                Spacer(minLength: 40)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Grok")
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.text, forType: .string)
                }
            }
        case .notice:
            HStack(spacing: 10) {
                VStack { Divider() }
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                VStack { Divider() }
            }
        }
    }
}

/// Grok's avatar in the conversation.
struct GrokAvatar: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(
                LinearGradient(colors: [.indigo, .purple], startPoint: .bottomLeading, endPoint: .topTrailing),
                in: .circle
            )
            .accessibilityHidden(true)
    }
}

/// An animated indicator for a reply that hasn't produced text yet.
struct TypingIndicator: View {
    var body: some View {
        Label {
            Text("Thinking…")
        } icon: {
            Image(systemName: "ellipsis")
                .symbolEffect(.variableColor.iterative, options: .repeat(.continuous))
        }
        .foregroundStyle(.secondary)
    }
}
