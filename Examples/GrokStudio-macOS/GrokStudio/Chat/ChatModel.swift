//
//  ChatModel.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels
import GrokLanguageModel
import Observation

/// A message that the Chat demo shows.
struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
        /// A note about the conversation, like a model change.
        case notice
    }

    let id = UUID()
    var role: Role
    var text: String
    var isStreaming = false
    var wasStopped = false
}

/// A streaming conversation with a Grok model.
///
/// Each conversation has its own `LanguageModelSession`, which keeps the
/// transcript that's sent with every request.
@Observable
final class ChatModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var session: LanguageModelSession
    private(set) var model: GrokModel
    private(set) var isResponding = false
    var draft = ""
    var error: PresentableError?

    @ObservationIgnored private var responseTask: Task<Void, Never>?

    /// The reply that's streaming, if there is one.
    @ObservationIgnored private var streamingReplyID: ChatMessage.ID?

    private static let instructions = """
        You are Grok, chatting inside GrokStudio, a Mac app that demonstrates the GrokLanguageModel \
        Swift package, which lets apps use Grok through Apple's Foundation Models framework. \
        Be concise, warm, and direct. Use Markdown when it helps: short paragraphs, lists, \
        and fenced code blocks that name their language. Write math as plain text, not LaTeX, with × for multiplication.
        """

    init(model: GrokModel = .grok4) {
        self.model = model
        session = Self.makeSession(model: model)
    }

    /// Creates a session for the conversation, starting from a transcript if
    /// you pass one.
    ///
    /// The session keeps prompts that fail or that you stop in its transcript,
    /// so that the model remembers everything the chat shows, and a follow-up
    /// like "continue" has context.
    private static func makeSession(model: GrokModel, transcript: Transcript? = nil) -> LanguageModelSession {
        let session = if let transcript {
            LanguageModelSession(model: model, transcript: transcript)
        } else {
            LanguageModelSession(model: model, instructions: instructions)
        }
        session.transcriptErrorHandlingPolicy = .preserveTranscript
        return session
    }

    /// Uses the model you specify for a conversation that hasn't started, so
    /// that the chat and the transcript inspector show the model that the
    /// first message goes to.
    func selectModel(_ newModel: GrokModel) {
        guard messages.isEmpty, !isResponding else { return }
        switchModel(to: newModel)
    }

    /// Sends the draft, or the prompt you pass, to the model you specify.
    func send(_ prompt: String? = nil, using model: GrokModel) {
        let text = (prompt ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        if prompt == nil {
            draft = ""
        }
        switchModel(to: model)
        error = nil

        messages.append(ChatMessage(role: .user, text: text))
        let reply = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(reply)
        isResponding = true
        streamingReplyID = reply.id

        let session = session
        responseTask = Task {
            var wasStopped = false
            do {
                for try await snapshot in session.streamResponse(to: text) {
                    updateMessage(reply.id) { $0.text = snapshot.content }
                }
            } catch is CancellationError {
                wasStopped = true
            } catch {
                if Task.isCancelled {
                    wasStopped = true
                } else {
                    self.error = PresentableError(error)
                }
            }
            // A canceled stream can also end without throwing.
            finishResponse(reply.id, wasStopped: wasStopped || Task.isCancelled)
        }
    }

    /// Stops the response that's in progress, keeping the text so far.
    func stop() {
        responseTask?.cancel()
    }

    /// Clears the conversation and starts a new session.
    func newConversation() {
        stop()
        // The canceled response finishes on its own, so you can start typing right away.
        responseTask = nil
        streamingReplyID = nil
        isResponding = false
        messages.removeAll()
        error = nil
        session = Self.makeSession(model: model)
    }

    /// Continues the conversation with a different model.
    ///
    /// The new session starts from the current transcript, so the new model
    /// sees the whole conversation. Grok models only send encrypted reasoning
    /// back to the model that produced it.
    private func switchModel(to newModel: GrokModel) {
        guard newModel != model else { return }
        model = newModel
        session = Self.makeSession(model: newModel, transcript: session.transcript)
        if !messages.isEmpty {
            messages.append(ChatMessage(role: .notice, text: "Switched to \(newModel.displayName)"))
        }
    }

    private func updateMessage(_ id: ChatMessage.ID, _ update: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        update(&messages[index])
    }

    private func finishResponse(_ id: ChatMessage.ID, wasStopped: Bool) {
        updateMessage(id) {
            $0.isStreaming = false
            $0.wasStopped = wasStopped
        }
        // Drop the placeholder for a reply that failed before it produced any text.
        messages.removeAll { $0.id == id && $0.text.isEmpty && !$0.wasStopped }

        // A reply from a conversation you cleared doesn't end a newer response.
        guard streamingReplyID == id else { return }
        streamingReplyID = nil
        isResponding = false
        responseTask = nil
    }
}
