//
//  PresentableError.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels
import GrokLanguageModel

/// An error, described for display in the app.
///
/// Grok models throw `GrokError` for problems that are specific to the xAI
/// API, and `LanguageModelError` for problems that any language model can
/// have, like rate limits and timeouts.
struct PresentableError: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var suggestion: String?

    /// A Boolean value that indicates whether changing settings could fix the error.
    var opensSettings = false

    init(title: String, message: String, suggestion: String? = nil, opensSettings: Bool = false) {
        self.title = title
        self.message = message
        self.suggestion = suggestion
        self.opensSettings = opensSettings
    }

    init(_ error: any Error) {
        switch error {
        case let error as GrokError:
            self.init(grokError: error)
        case let error as LanguageModelError:
            self.init(languageModelError: error)
        case let error as LanguageModelSession.ToolCallError:
            self.init(
                title: "A Tool Failed",
                message: "\(error.tool.name): \(error.underlyingError.localizedDescription)"
            )
        case let error as URLError:
            self.init(title: "Network Error", message: error.localizedDescription)
        default:
            self.init(title: "Something Went Wrong", message: error.localizedDescription)
        }
    }

    private init(grokError error: GrokError) {
        switch error {
        case .missingAPIKey:
            self.init(
                title: "Add an API Key",
                message: "GrokStudio needs an xAI API key to talk to Grok.",
                suggestion: "Paste a key in Settings, or set GROK_API_KEY in the environment variables of an unshared copy of the scheme.",
                opensSettings: true
            )
        case .requestFailed(let statusCode, let code, let message):
            // The xAI API rejects an invalid key with HTTP 400, 401, or 403.
            let mentionsKey = message.localizedCaseInsensitiveContains("key")
                || code?.localizedCaseInsensitiveContains("key") == true
            let isAuthenticationError = statusCode == 401 || statusCode == 403 || (statusCode == 400 && mentionsKey)
            self.init(
                title: isAuthenticationError ? "Check Your API Key" : "Request Failed",
                message: message,
                suggestion: "HTTP \(statusCode)" + (code.map { " · \($0)" } ?? ""),
                opensSettings: isAuthenticationError
            )
        case .generationFailed(let code, let message):
            self.init(title: "Generation Failed", message: message, suggestion: code)
        case .invalidResponse(let description):
            self.init(title: "Unexpected Response", message: description)
        case .imageEncodingFailed:
            self.init(title: "Couldn't Send the Image", message: error.localizedDescription)
        }
    }

    private init(languageModelError error: LanguageModelError) {
        switch error {
        case .rateLimited(let context):
            let retry = context.resetDate.map { "Try again \($0.formatted(.relative(presentation: .named)))." }
            self.init(title: "Rate Limited", message: context.debugDescription, suggestion: retry)
        case .timeout(let context):
            self.init(
                title: "Request Timed Out",
                message: context.debugDescription,
                suggestion: "Try again, or choose a faster model or a lighter reasoning level."
            )
        case .guardrailViolation(let context):
            self.init(title: "Blocked by the Content Filter", message: context.debugDescription)
        case .refusal(let context):
            self.init(title: "Grok Declined", message: context.debugDescription)
        case .contextSizeExceeded(let context):
            self.init(
                title: "Conversation Too Long",
                message: "The conversation uses \(context.tokenCount.formatted()) of \(context.contextSize.formatted()) tokens.",
                suggestion: "Start a new conversation."
            )
        case .unsupportedCapability(let context):
            self.init(
                title: "Not Supported by This Model",
                message: context.debugDescription,
                suggestion: "Choose a different model from the toolbar."
            )
        default:
            self.init(title: "Generation Failed", message: error.localizedDescription)
        }
    }
}
