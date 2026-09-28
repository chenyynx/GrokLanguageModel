//
//  ChatView.swift
//  GrokChat
//
//  Created by Marcus Arnett on 9/28/26.
//

import CoreGraphics
import GrokLanguageModel
import SwiftUI

/// The chat screen: the conversation, a composer, and a settings sheet.
struct ChatView: View {
    @Environment(Conversation.self) private var conversation
    @Environment(ChatSettings.self) private var settings

    @State private var draft = ""
    @State private var attachment: CGImage?
    @State private var isShowingSettings = false
    @State private var scrollPosition = ScrollPosition(edge: .bottom)

    var body: some View {
        NavigationStack {
            Group {
                if conversation.messages.isEmpty {
                    EmptyChatView { conversation.send($0) }
                } else {
                    messageList
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if let problem = conversation.problem {
                        ProblemBanner(
                            problem: problem,
                            retry: conversation.retry,
                            openSettings: { isShowingSettings = true },
                            dismiss: { conversation.problem = nil }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    ComposerView(
                        text: $draft,
                        image: $attachment,
                        isResponding: conversation.isResponding,
                        send: send,
                        stop: conversation.stop
                    )
                }
                .animation(.snappy, value: conversation.problem != nil)
            }
            .navigationTitle("GrokChat")
            .navigationSubtitle(settings.preset.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Chat", systemImage: "square.and.pencil") {
                        conversation.startNewChat()
                        draft = ""
                        attachment = nil
                    }
                    .disabled(conversation.messages.isEmpty)
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
        }
        .task {
            conversation.sendDemoPromptIfNeeded()
        }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(conversation.messages) { message in
                    MessageView(message: message)
                }
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: conversation.messages.count) {
            withAnimation {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
    }

    private func send() {
        conversation.send(draft, image: attachment)
        draft = ""
        attachment = nil
    }
}

// MARK: - Empty state

/// The screen for a new chat, which suggests prompts to try.
private struct EmptyChatView: View {
    var select: (String) -> Void

    private struct Suggestion: Identifiable {
        var title: String
        var prompt: String
        var systemImage: String
        var id: String { prompt }
    }

    private let suggestions = [
        Suggestion(title: "Check the time", prompt: "What time is it in Tokyo right now?", systemImage: "clock"),
        Suggestion(title: "Explain a concept", prompt: "Explain Swift concurrency in three short bullet points.", systemImage: "swift"),
        Suggestion(title: "Write a poem", prompt: "Write a haiku about a rocket landing at sunrise.", systemImage: "sparkles"),
        Suggestion(title: "Plan a trip", prompt: "Plan a relaxing weekend in Kyoto.", systemImage: "map"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                    Text("Chat with Grok")
                        .font(.title2.bold())
                    Text("SpaceXAI's Grok models, running through Apple's Foundation Models framework.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            select(suggestion.prompt)
                        } label: {
                            SuggestionRow(title: suggestion.title, prompt: suggestion.prompt, systemImage: suggestion.systemImage)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Label("Attach a photo to ask Grok about it.", systemImage: "photo")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct SuggestionRow: View {
    var title: String
    var prompt: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(prompt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.circle.fill")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.fill.quinary, in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
    }
}

// MARK: - Problems

/// A banner that describes a failed request and how to recover from it.
private struct ProblemBanner: View {
    var problem: Conversation.Problem
    var retry: () -> Void
    var openSettings: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(problem.message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 20) {
                    if problem.needsAPIKey {
                        Button("Open Settings", action: openSettings)
                    }
                    if problem.canRetry {
                        Button("Try Again", action: retry)
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .glassEffect(.regular.tint(.orange.opacity(0.12)), in: .rect(cornerRadius: 20))
        .padding(.horizontal)
    }
}

#Preview {
    let settings = ChatSettings()
    ChatView()
        .environment(settings)
        .environment(Conversation(settings: settings))
}
