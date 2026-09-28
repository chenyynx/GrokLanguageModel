//
//  GrokError.swift
//  GrokLanguageModel
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels

/// Errors that a Grok model can throw in addition to `LanguageModelError`.
///
/// The package only adds cases to this enumeration, or changes their
/// associated values, in a new major version, so a `switch` over it that
/// handles every case keeps compiling throughout a major version. Within a
/// major version, new kinds of failures surface through an existing case or
/// as a `LanguageModelError`.
public enum GrokError: Error, Sendable {
    /// No API key is available for a request to the xAI API.
    ///
    /// Set ``GrokConfiguration/apiKey`` or the `GROK_API_KEY` environment variable.
    case missingAPIKey

    /// The xAI API rejected the request.
    ///
    /// This includes a request whose conversation doesn't fit in the model's
    /// context window. The package doesn't throw
    /// `LanguageModelError.contextSizeExceeded(_:)`.
    case requestFailed(statusCode: Int, code: String?, message: String)

    /// The model failed while it generated a response.
    case generationFailed(code: String?, message: String)

    /// The server sent a response that couldn't be understood.
    case invalidResponse(String)

    /// An image attachment couldn't be encoded for the request.
    case imageEncodingFailed
}

extension GrokError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No xAI API key is configured. Set GrokConfiguration.default.apiKey or the GROK_API_KEY environment variable."
        case .requestFailed(let statusCode, _, let message):
            "The xAI API rejected the request (HTTP \(statusCode)): \(message)"
        case .generationFailed(_, let message):
            "Grok failed to generate a response: \(message)"
        case .invalidResponse(let description):
            "The xAI API sent an invalid response: \(description)"
        case .imageEncodingFailed:
            "An image attachment couldn't be encoded as JPEG or PNG."
        }
    }
}

extension GrokError {
    /// Maps an unsuccessful HTTP response to the error that best describes it.
    static func from(statusCode: Int, retryAfter: String?, body: Data) -> any Error {
        let (code, message) = errorDetails(in: body)
        switch statusCode {
        case 429:
            let resetDate = retryAfter.flatMap(TimeInterval.init).map { Date(timeIntervalSinceNow: $0) }
            return LanguageModelError.rateLimited(.init(resetDate: resetDate, debugDescription: message))
        default:
            return GrokError.requestFailed(statusCode: statusCode, code: code, message: message)
        }
    }

    /// Extracts an error code and message from an xAI error body, which is
    /// either `{"code": ..., "error": "..."}` or `{"error": {"code": ..., "message": "..."}}`.
    static func errorDetails(in body: Data) -> (code: String?, message: String) {
        let fallback = String(decoding: body, as: UTF8.self)
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: body) else {
            return (nil, fallback.isEmpty ? "Unknown error" : fallback)
        }
        if let error = json["error"], error.stringValue == nil {
            return (error["code"]?.textValue, error["message"]?.stringValue ?? fallback)
        }
        let message = json["error"]?.stringValue ?? json["message"]?.stringValue ?? fallback
        return (json["code"]?.textValue, message)
    }
}
