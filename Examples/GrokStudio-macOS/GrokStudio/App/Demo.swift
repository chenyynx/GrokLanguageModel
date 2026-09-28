//
//  Demo.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation

/// A feature demo in the sidebar.
enum Demo: String, CaseIterable, Identifiable {
    case chat
    case structuredOutput
    case tools
    case reasoning
    case vision

    var id: Self { self }

    /// The demo to show at launch: the one that the `-demo` launch argument
    /// names, like `-demo tools`, or Chat.
    static var initial: Demo {
        UserDefaults.standard.string(forKey: "demo").flatMap(Demo.init(rawValue:)) ?? .chat
    }

    var title: String {
        switch self {
        case .chat: "Chat"
        case .structuredOutput: "Structured Output"
        case .tools: "Tools"
        case .reasoning: "Reasoning"
        case .vision: "Vision"
        }
    }

    var subtitle: String {
        switch self {
        case .chat: "Streaming conversation"
        case .structuredOutput: "@Generable trip planner"
        case .tools: "Weather and calculator tools"
        case .reasoning: "Reasoning levels and summaries"
        case .vision: "Ask about an image"
        }
    }

    var systemImage: String {
        switch self {
        case .chat: "bubble.left.and.text.bubble.right"
        case .structuredOutput: "curlybraces.square"
        case .tools: "wrench.and.screwdriver"
        case .reasoning: "brain"
        case .vision: "photo.on.rectangle.angled"
        }
    }
}
