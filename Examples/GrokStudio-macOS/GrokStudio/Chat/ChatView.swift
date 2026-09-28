//
//  ChatView.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import GrokLanguageModel
import SwiftUI

/// The Chat demo: a streaming conversation, with the session's live
/// transcript in an inspector.
struct ChatView: View {
    @Bindable var chat: ChatModel
    @Environment(AppSettings.self) private var settings
    @AppStorage("showsChatTranscript") private var showsTranscript = true

    var body: some View {
        VStack(spacing: 0) {
            if chat.messages.isEmpty {
                ChatEmptyState { prompt in
                    chat.send(prompt, using: settings.selectedModel)
                }
            } else {
                messageList
            }

            VStack(spacing: 10) {
                if let error = chat.error {
                    ErrorBanner(error: error) { chat.error = nil }
                }
                PromptComposer(
                    text: $chat.draft,
                    placeholder: "Message \(settings.selectedModel.displayName)",
                    isResponding: chat.isResponding,
                    onSend: { chat.send(using: settings.selectedModel) },
                    onStop: chat.stop
                )
            }
            .frame(maxWidth: 780)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .animation(.snappy, value: chat.error?.id)
        }
        .navigationTitle("Chat")
        .navigationSubtitle(chat.model.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Conversation", systemImage: "square.and.pencil") {
                    chat.newConversation()
                    chat.selectModel(settings.selectedModel)
                }
                .keyboardShortcut("n")
                .disabled(chat.messages.isEmpty && chat.error == nil)
                .help("Start a new conversation (⌘N)")
            }
        }
        .transcriptInspector(for: chat.session, isResponding: chat.isResponding, isPresented: $showsTranscript)
        .onChange(of: settings.selectedModel, initial: true) { _, model in
            // Until the conversation starts, follow the toolbar's model picker.
            chat.selectModel(model)
        }
        .task {
            // Screenshot hook: `-demoPrompt "…"` sends a prompt once at launch.
            if let prompt = settings.consumeDemoPrompt() {
                chat.send(prompt, using: settings.selectedModel)
            }
        }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(chat.messages) { message in
                    MessageRow(message: message)
                }
            }
            .frame(maxWidth: 780)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
    }
}

/// Suggestions for starting a conversation.
private struct ChatEmptyState: View {
    var onSelect: (String) -> Void

    private let suggestions = [
        ("swift", "Explain Swift's structured concurrency to someone who knows GCD."),
        ("text.quote", "Write a haiku about a sunrise on Mars."),
        ("chevron.left.forwardslash.chevron.right", "Show me a Swift function that debounces an AsyncSequence."),
        ("doc.text", "Draft friendly release notes for version 1.0.0 of a Swift package."),
    ]

    var body: some View {
        // Centered when it fits, and scrollable in a small window.
        ScrollView {
            content
                .padding(24)
                .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
    }

    private var content: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolEffect(.breathe, options: .repeat(.continuous))
                Text("Chat with Grok")
                    .font(.largeTitle.bold())
                Text("Every reply streams through `LanguageModelSession.streamResponse(to:)`.")
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 12)], spacing: 12) {
                ForEach(suggestions, id: \.1) { symbol, prompt in
                    Button {
                        onSelect(prompt)
                    } label: {
                        Label(prompt, systemImage: symbol)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .padding(12)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                }
            }
            .frame(maxWidth: 720)
        }
    }
}
