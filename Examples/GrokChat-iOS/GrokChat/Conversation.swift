//
//  Conversation.swift
//  GrokChat
//
//  Created by Marcus Arnett on 9/28/26.
//

import CoreGraphics
import Foundation
import FoundationModels
import GrokLanguageModel
import Observation

/// A chat with Grok: the messages on screen and the language model session
/// behind them.
@Observable
final class Conversation {
    /// A problem that the chat screen shows in a banner.
    struct Problem {
        var message: String

        /// Whether adding an API key in Settings fixes the problem.
        var needsAPIKey = false

        /// Whether sending the failed message again might succeed.
        var canRetry = false
    }

    /// The messages in the conversation, oldest first.
    private(set) var messages: [ChatMessage] = []

    /// The last problem, if the chat screen hasn't dismissed it.
    var problem: Problem?

    /// Whether Grok is generating a reply.
    var isResponding: Bool { activeReplyID != nil }

    private var activeReplyID: ChatMessage.ID?
    @ObservationIgnored private let settings: ChatSettings
    @ObservationIgnored private var session: LanguageModelSession?
    @ObservationIgnored private var sessionSetup: SessionSetup?
    @ObservationIgnored private var responseTask: Task<Void, Never>?
    @ObservationIgnored private var failedPrompt: Prompt?
    @ObservationIgnored private var hasSentDemoPrompt = false

    /// The model and tools that a session was created with.
    private struct SessionSetup: Equatable {
        var model: GrokModel
        var usesTimeTool: Bool
    }

    /// A message that the user sent, and where its entries start in the
    /// session's transcript.
    private struct Prompt {
        var text: String
        var image: CGImage?
        var transcriptStart: Int
    }

    private static let instructions = """
        You are Grok, chatting with the user in GrokChat, a sample iOS app for the GrokLanguageModel \
        Swift package. Keep answers concise and friendly. The app renders inline Markdown, like bold, \
        italics, code, and links, but not headings or tables.
        """

    init(settings: ChatSettings) {
        self.settings = settings
    }

    // MARK: - Chatting

    /// Sends a message, with an optional photo, and streams Grok's reply.
    func send(_ text: String, image: CGImage? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isResponding, !text.isEmpty || image != nil else { return }

        problem = nil
        failedPrompt = nil
        messages.append(ChatMessage(role: .user, text: text, image: image))
        let reply = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(reply)
        activeReplyID = reply.id

        let session = currentSession()
        let prompt = Prompt(text: text, image: image, transcriptStart: session.transcript.count)
        responseTask = Task {
            await streamReply(to: prompt, in: session, replyID: reply.id)
        }
    }

    /// Stops the reply that Grok is generating.
    func stop() {
        responseTask?.cancel()
    }

    /// Sends the last message again after it failed.
    func retry() {
        guard !isResponding, let prompt = failedPrompt,
              let index = messages.lastIndex(where: { $0.role == .user }) else { return }

        // The session keeps a failed prompt, and any partial reply to it, in
        // its transcript, so remove them before sending the prompt again.
        if let session, session.transcript.count > prompt.transcriptStart {
            session.transcript.removeSubrange(prompt.transcriptStart...)
        }
        messages.removeSubrange(index...)
        send(prompt.text, image: prompt.image)
    }

    /// Clears the conversation and starts over with a new session.
    func startNewChat() {
        responseTask?.cancel()
        responseTask = nil
        activeReplyID = nil
        messages.removeAll()
        problem = nil
        failedPrompt = nil
        session = nil
        sessionSetup = nil
    }

    /// Sends the prompt in the `demoPrompt` user default, once per launch.
    ///
    /// Pass `-demoPrompt "<prompt>"` as a launch argument to fill the screen for
    /// screenshots and UI tests.
    func sendDemoPromptIfNeeded() {
        guard !hasSentDemoPrompt, let prompt = UserDefaults.standard.string(forKey: "demoPrompt") else { return }
        hasSentDemoPrompt = true
        send(prompt)
    }

    // MARK: - Streaming

    private func streamReply(to prompt: Prompt, in session: LanguageModelSession, replyID: ChatMessage.ID) async {
        do {
            // The prompt builder combines text and image attachments in one prompt.
            let stream = session.streamResponse {
                prompt.text.isEmpty ? "What's in this photo?" : prompt.text
                if let image = prompt.image {
                    Attachment(image)
                }
            }
            for try await snapshot in stream {
                updateMessage(replyID) { $0.update(with: snapshot) }
            }
        } catch let error where !Task.isCancelled && !(error is CancellationError) {
            handle(error, replyID: replyID, prompt: prompt)
        } catch {
            // Stopping a reply cancels the task, which ends the stream.
        }

        let wasStopped = Task.isCancelled
        updateMessage(replyID) { reply in
            reply.isStreaming = false
            reply.wasStopped = wasStopped
        }
        if activeReplyID == replyID {
            activeReplyID = nil
            responseTask = nil
        }
    }

    private func handle(_ error: any Error, replyID: ChatMessage.ID, prompt: Prompt) {
        if let index = messages.firstIndex(where: { $0.id == replyID }), messages[index].text.isEmpty {
            messages.remove(at: index)
        }
        failedPrompt = prompt
        switch error {
        case GrokError.missingAPIKey:
            problem = Problem(message: "Add your xAI API key in Settings to start chatting.", needsAPIKey: true, canRetry: true)
        case LanguageModelError.contextSizeExceeded:
            // Sending the same prompt again would overflow the context again.
            problem = Problem(message: Self.message(for: error))
        default:
            problem = Problem(message: Self.message(for: error), canRetry: true)
        }
    }

    private func updateMessage(_ id: ChatMessage.ID, _ update: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        update(&messages[index])
    }

    /// A description of an error from a Grok model.
    ///
    /// `GrokError` describes problems with the xAI API, and the package maps
    /// rate limits, timeouts, and content filtering to `LanguageModelError`.
    private static func message(for error: any Error) -> String {
        guard let error = error as? LanguageModelError else {
            return error.localizedDescription
        }
        switch error {
        case .rateLimited(let rateLimit):
            guard let resetDate = rateLimit.resetDate else {
                return "Grok is receiving too many requests. Try again in a moment."
            }
            return "Grok is receiving too many requests. Try again \(resetDate.formatted(.relative(presentation: .named)))."
        case .timeout:
            return "Grok took too long to respond. Check your connection and try again."
        case .guardrailViolation:
            return "Grok's content filter stopped this response."
        case .refusal:
            return "Grok declined to respond to this request."
        case .contextSizeExceeded:
            return "This conversation is too long for the model. Start a new chat to continue."
        default:
            return error.localizedDescription
        }
    }

    // MARK: - Sessions

    /// Returns a session for the model and tools in Settings.
    ///
    /// When the settings change mid-conversation, the new session starts from
    /// the old session's transcript, so the conversation carries over.
    private func currentSession() -> LanguageModelSession {
        let setup = SessionSetup(model: settings.model, usesTimeTool: settings.isTimeToolEnabled)
        if let session, setup == sessionSetup {
            return session
        }

        let tools: [any Tool] = setup.usesTimeTool ? [CurrentTimeTool()] : []
        let newSession = if let session {
            LanguageModelSession(model: setup.model, tools: tools, transcript: session.transcript)
        } else {
            LanguageModelSession(model: setup.model, tools: tools, instructions: Self.instructions)
        }
        // Keep prompts that fail or that the user stops in the transcript, so
        // that the session remembers everything the chat screen shows.
        newSession.transcriptErrorHandlingPolicy = .preserveTranscript
        session = newSession
        sessionSetup = setup
        return newSession
    }
}
