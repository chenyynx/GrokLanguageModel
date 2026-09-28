//
//  Transcript+Display.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import FoundationModels
import SwiftUI

/// A labeled value that describes part of a transcript entry.
struct TranscriptDetail: Identifiable {
    var label: String
    var value: String
    var id: String { label }
}

extension Transcript.Entry {
    /// The name of the entry's kind, like "Prompt" or "Tool Calls".
    var kindTitle: String {
        switch self {
        case .instructions: "Instructions"
        case .prompt: "Prompt"
        case .reasoning: "Reasoning"
        case .toolCalls: "Tool Calls"
        case .toolOutput: "Tool Output"
        case .response: "Response"
        @unknown default: "Entry"
        }
    }

    var systemImage: String {
        switch self {
        case .instructions: "list.bullet.rectangle"
        case .prompt: "person.fill"
        case .reasoning: "brain"
        case .toolCalls: "wrench.and.screwdriver.fill"
        case .toolOutput: "tray.and.arrow.down.fill"
        case .response: "sparkles"
        @unknown default: "questionmark.square"
        }
    }

    var tint: Color {
        switch self {
        case .instructions: .gray
        case .prompt: .blue
        case .reasoning: .purple
        case .toolCalls: .orange
        case .toolOutput: .teal
        case .response: .accentColor
        @unknown default: .secondary
        }
    }

    /// Whether the entry's text is JSON or code that reads best in a monospaced font.
    var prefersMonospacedText: Bool {
        switch self {
        case .toolCalls, .toolOutput: true
        default: false
        }
    }

    /// The entry's full text, like a prompt's text or a tool call's arguments.
    var displayText: String {
        switch self {
        case .instructions(let instructions):
            instructions.segments.plainText
        case .prompt(let prompt):
            prompt.segments.plainText
        case .reasoning(let reasoning):
            reasoning.segments.plainText
        case .toolCalls(let calls):
            calls.map { "\($0.toolName)(\($0.arguments.jsonString))" }.joined(separator: "\n")
        case .toolOutput(let output):
            output.segments.plainText
        case .response(let response):
            response.segments.plainText
        @unknown default:
            description
        }
    }

    /// A short preview of the entry for a collapsed row.
    var preview: String {
        switch self {
        case .reasoning(let reasoning) where reasoning.segments.plainText.isEmpty:
            reasoning.signature == nil ? "Thinking…" : "Encrypted reasoning only"
        case .toolCalls(let calls):
            calls.map(\.toolName).joined(separator: ", ")
        case .toolOutput(let output):
            "\(output.toolName): \(output.segments.plainText)"
        default:
            displayText.isEmpty ? "Empty" : displayText
        }
    }

    /// Details about the entry, like the model that produced it.
    var details: [TranscriptDetail] {
        var details: [TranscriptDetail] = []
        switch self {
        case .instructions(let instructions):
            if !instructions.toolDefinitions.isEmpty {
                details.append(.init(label: "Tools", value: instructions.toolDefinitions.map(\.name).joined(separator: ", ")))
            }
        case .prompt(let prompt):
            if let level = prompt.contextOptions.reasoningLevel {
                details.append(.init(label: "Reasoning level", value: level.displayName))
            }
            if let mode = prompt.options.toolCallingMode {
                details.append(.init(label: "Tool calling", value: mode.displayName))
            }
            if let format = prompt.responseFormat {
                details.append(.init(label: "Response format", value: format.name))
            }
            details += Self.details(from: prompt.metadata)
        case .reasoning(let reasoning):
            if let signature = reasoning.signature {
                details.append(.init(label: "Signature", value: "\(signature.count.formatted()) bytes"))
            }
            details += Self.details(from: reasoning.metadata)
        case .toolCalls(let calls):
            details += Self.details(from: calls.first?.metadata ?? [:])
        case .toolOutput(let output):
            details.append(.init(label: "Call ID", value: output.id))
        case .response(let response):
            details += Self.details(from: response.metadata)
        @unknown default:
            break
        }
        return details
    }

    private static func details(from metadata: [String: GeneratedContent]) -> [TranscriptDetail] {
        metadata.keys.sorted().map { key in
            TranscriptDetail(label: key, value: metadata[key]?.displayText ?? "")
        }
    }
}

extension [Transcript.Segment] {
    /// The segments' text, with a placeholder for each attachment.
    var plainText: String {
        map(\.plainText).joined(separator: "\n")
    }
}

extension Transcript.Segment {
    /// The segment's text, with a placeholder for an attachment.
    var plainText: String {
        switch self {
        case .text(let text):
            text.content
        case .structure(let structure):
            structure.content.jsonString
        case .attachment(let attachment):
            attachment.label.map { "[Image: \($0)]" } ?? "[Image]"
        @unknown default:
            description
        }
    }
}

extension GeneratedContent {
    /// The content as display text: a string without quotes, or JSON otherwise.
    var displayText: String {
        if case .string(let string) = kind {
            string
        } else {
            jsonString
        }
    }
}

extension ContextOptions.ReasoningLevel {
    var displayName: String {
        switch self {
        case .light: "light"
        case .moderate: "moderate"
        case .deep: "deep"
        case .custom(let value): "custom(\"\(value)\")"
        @unknown default: "unknown"
        }
    }
}

extension GenerationOptions.ToolCallingMode {
    var displayName: String {
        switch kind {
        case .allowed: "allowed"
        case .required: "required"
        case .disallowed: "disallowed"
        @unknown default: "unknown"
        }
    }
}
