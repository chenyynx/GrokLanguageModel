//
//  GrokModel+Executor.swift
//  GrokLanguageModel
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels

extension GrokModel {
    /// The executor that runs Grok requests with the xAI Responses API.
    ///
    /// The framework creates executors from ``GrokModel/executorConfiguration``,
    /// so you don't need to create one yourself.
    public struct Executor: LanguageModelExecutor {
        public typealias Model = GrokModel

        /// The connection settings that the executor uses.
        public let configuration: GrokConfiguration

        public init(configuration: GrokConfiguration) {
            self.configuration = configuration
        }

        nonisolated(nonsending) public func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: GrokModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            let body = try ResponsesRequest(request: request, model: model)
            let urlRequest = try configuration.makeURLRequest(body: body)
            do {
                let (bytes, response) = try await configuration.urlSession.bytes(for: urlRequest)
                try await Self.validate(response, bytes: bytes)

                var parser = ServerSentEventParser()
                var translator = ResponseStreamTranslator(modelName: model.name)
                let decoder = JSONDecoder()
                for try await byte in bytes {
                    guard let event = parser.consume(byte) else { continue }
                    try await Self.forward(event, through: &translator, to: channel, decoder: decoder)
                }
                if let event = parser.finish() {
                    try await Self.forward(event, through: &translator, to: channel, decoder: decoder)
                }
                try translator.finish()
            } catch let error as URLError where error.code == .timedOut {
                throw LanguageModelError.timeout(.init(debugDescription: error.localizedDescription))
            }
        }

        nonisolated(nonsending) private static func forward(
            _ event: ServerSentEvent,
            through translator: inout ResponseStreamTranslator,
            to channel: LanguageModelExecutorGenerationChannel,
            decoder: JSONDecoder
        ) async throws {
            guard let streamEvent = StreamEvent(event, decoder: decoder) else { return }
            for output in try translator.translate(streamEvent) {
                await channel.send(output.channelEvent)
            }
        }

        /// Throws the error that an unsuccessful response describes.
        nonisolated(nonsending) private static func validate(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
            guard let response = response as? HTTPURLResponse else {
                throw GrokError.invalidResponse("The server didn't send an HTTP response.")
            }
            guard !(200..<300).contains(response.statusCode) else { return }
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= 65_536 { break }
            }
            throw GrokError.from(
                statusCode: response.statusCode,
                retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
                body: body
            )
        }
    }
}
