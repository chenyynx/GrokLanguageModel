//
//  ChatMessage.swift
//  GrokChat
//
//  Created by Marcus Arnett on 9/28/26.
//

import CoreGraphics
import Foundation
import FoundationModels

/// A message on the chat screen.
struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role

    /// The message's text, which grows while Grok streams a reply.
    var text: String

    /// A photo that the user attached to the message.
    var image: CGImage?

    /// The summary of the model's reasoning before it replied.
    var reasoning = ""

    /// The names of the tools that the model called while it replied, in order.
    var toolCalls: [String] = []

    /// The tokens that the reply used.
    var usage: LanguageModelSession.Usage?

    /// Whether Grok is still generating the reply.
    var isStreaming = false

    /// Whether the user stopped the reply before it finished.
    var wasStopped = false
}

extension ChatMessage {
    /// Updates a reply from the latest snapshot of a streaming response.
    ///
    /// Besides the text, a snapshot has the transcript entries that the
    /// response has added so far, like the model's reasoning and tool calls,
    /// and the tokens it has used.
    mutating func update(with snapshot: LanguageModelSession.ResponseStream<String>.Snapshot) {
        var reasoning: [String] = []
        var toolCalls: [String] = []
        for entry in snapshot.transcriptEntries {
            switch entry {
            case .reasoning(let entry):
                reasoning.append(entry.segments.text)
            case .toolCalls(let calls):
                toolCalls.append(contentsOf: calls.map(\.toolName))
            default:
                break
            }
        }

        text = snapshot.content
        self.reasoning = reasoning
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        self.toolCalls = toolCalls
        usage = snapshot.usage
    }
}

extension [Transcript.Segment] {
    /// The text of the segments, ignoring attachments and structured content.
    var text: String {
        compactMap { segment in
            if case .text(let text) = segment { text.content } else { nil }
        }
        .joined()
    }
}
