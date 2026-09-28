//
//  GrokChatApp.swift
//  GrokChat
//
//  Created by Marcus Arnett on 9/28/26.
//

import SwiftUI

/// A chat app that talks to SpaceXAI's Grok models through Apple's
/// Foundation Models framework, using the GrokLanguageModel package.
@main
struct GrokChatApp: App {
    @State private var settings: ChatSettings
    @State private var conversation: Conversation

    init() {
        // Creating the settings loads the API key saved in the Keychain into
        // `GrokConfiguration.default`, before any session sends a request.
        let settings = ChatSettings()
        _settings = State(initialValue: settings)
        _conversation = State(initialValue: Conversation(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(settings)
                .environment(conversation)
        }
    }
}
