//
//  MockServer.swift
//  GrokLanguageModelTests
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import Synchronization
@testable import GrokLanguageModel

/// A fake xAI server that records requests and replies with canned responses.
final class MockServer: Sendable {
    struct Reply: Sendable {
        var statusCode = 200
        var headers: [String: String] = ["Content-Type": "text/event-stream"]
        var body: Data
        /// The pieces of the body to send one at a time, `chunkInterval` apart,
        /// or `nil` to send the whole body at once.
        var chunks: [Data]?
        var chunkInterval: TimeInterval = 0
    }

    private let id = UUID().uuidString
    private let replies: Mutex<[Reply]>
    private let recordedRequests = Mutex<[JSONValue]>([])
    private let recordedBodies = Mutex<[Data]>([])

    /// Creates a server that sends the replies in order, one per request.
    init(replies: [Reply]) {
        self.replies = Mutex(replies)
        MockURLProtocol.servers.withLock { $0[id] = self }
    }

    /// The JSON bodies of the requests the server received.
    var requests: [JSONValue] { recordedRequests.withLock { $0 } }

    /// The raw bodies of the requests the server received, as they were sent.
    var bodies: [Data] { recordedBodies.withLock { $0 } }

    /// A model that sends its requests to this server.
    func model(_ model: GrokModel = .grok4_3) -> GrokModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        var model = model
        model.configuration = GrokConfiguration(
            apiKey: "test-key",
            additionalHeaders: [MockURLProtocol.serverHeader: id],
            urlSession: URLSession(configuration: configuration)
        )
        return model
    }

    fileprivate func reply(to request: URLRequest) -> Reply {
        if let body = request.bodyData {
            recordedBodies.withLock { $0.append(body) }
            if let json = try? JSONDecoder().decode(JSONValue.self, from: body) {
                recordedRequests.withLock { $0.append(json) }
            }
        }
        return replies.withLock { replies in
            replies.isEmpty ? Reply(statusCode: 500, body: Data("No more replies".utf8)) : replies.removeFirst()
        }
    }
}

extension MockServer.Reply {
    /// A successful streaming reply made of Responses API events.
    ///
    /// - Parameters:
    ///   - events: The JSON of each event.
    ///   - interval: The time to wait before sending each event, like a server
    ///     that generates them over time, or `nil` to send them all at once.
    static func events(_ events: [String], interval: TimeInterval? = nil) -> Self {
        let chunks = events.map { Data("event: message\ndata: \($0)\n\n".utf8) }
        var reply = Self(body: chunks.reduce(Data(), +))
        if let interval {
            reply.chunks = chunks
            reply.chunkInterval = interval
        }
        return reply
    }

    static func error(statusCode: Int, headers: [String: String] = [:], json: String) -> Self {
        Self(statusCode: statusCode, headers: headers.merging(["Content-Type": "application/json"]) { a, _ in a }, body: Data(json.utf8))
    }
}

final class MockURLProtocol: URLProtocol {
    static let serverHeader = "X-Mock-Server"
    static let servers = Mutex<[String: MockServer]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: Self.serverHeader),
              let server = Self.servers.withLock({ $0[id] }),
              let url = request.url
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let reply = server.reply(to: request)
        let response = HTTPURLResponse(url: url, statusCode: reply.statusCode, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        guard let chunks = reply.chunks else {
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        // Client callbacks belong on the thread that started loading, so
        // schedule each chunk on this thread's run loop.
        let modes = [RunLoop.current.currentMode ?? .default]
        for (index, chunk) in chunks.enumerated() {
            perform(#selector(send(_:)), with: chunk, afterDelay: reply.chunkInterval * Double(index + 1), inModes: modes)
        }
        perform(#selector(finish), with: nil, afterDelay: reply.chunkInterval * Double(chunks.count + 1), inModes: modes)
    }

    override func stopLoading() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
    }

    @objc private func send(_ chunk: Data) {
        client?.urlProtocol(self, didLoad: chunk)
    }

    @objc private func finish() {
        client?.urlProtocolDidFinishLoading(self)
    }
}

private extension URLRequest {
    /// The body of the request, which URL sessions move into a stream.
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Builders for Responses API stream events.
enum Events {
    static func created(id: String = "resp_1", model: String = "grok-4.3") -> String {
        #"{"type":"response.created","response":{"id":"\#(id)","model":"\#(model)","output":[]}}"#
    }

    static func itemAdded(_ index: Int, type: String, callID: String? = nil, name: String? = nil) -> String {
        var item = #""type":"\#(type)""#
        if let callID { item += #","call_id":"\#(callID)""# }
        if let name { item += #","name":"\#(name)","arguments":"""# }
        return #"{"type":"response.output_item.added","output_index":\#(index),"item":{\#(item)}}"#
    }

    static func reasoningDelta(_ index: Int, _ delta: String, summaryIndex: Int = 0) -> String {
        #"{"type":"response.reasoning_summary_text.delta","output_index":\#(index),"summary_index":\#(summaryIndex),"delta":\#(quoted(delta))}"#
    }

    static func reasoningDone(_ index: Int, summary: String, encryptedContent: String?) -> String {
        let encrypted = encryptedContent.map { #","encrypted_content":\#(quoted($0))"# } ?? ""
        return #"{"type":"response.output_item.done","output_index":\#(index),"item":{"type":"reasoning","summary":[{"type":"summary_text","text":\#(quoted(summary))}]\#(encrypted)}}"#
    }

    static func textDelta(_ index: Int, _ delta: String) -> String {
        #"{"type":"response.output_text.delta","output_index":\#(index),"content_index":0,"delta":\#(quoted(delta))}"#
    }

    static func messageDone(_ index: Int, text: String) -> String {
        #"{"type":"response.output_item.done","output_index":\#(index),"item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":\#(quoted(text))}]}}"#
    }

    static func argumentsDelta(_ index: Int, _ delta: String) -> String {
        #"{"type":"response.function_call_arguments.delta","output_index":\#(index),"delta":\#(quoted(delta))}"#
    }

    static func functionCallDone(_ index: Int, callID: String, name: String, arguments: String) -> String {
        #"{"type":"response.output_item.done","output_index":\#(index),"item":{"type":"function_call","call_id":"\#(callID)","name":"\#(name)","arguments":\#(quoted(arguments))}}"#
    }

    static func completed(input: Int = 10, cached: Int = 2, output: Int = 20, reasoning: Int = 5) -> String {
        #"{"type":"response.completed","response":{"id":"resp_1","status":"completed","usage":{"input_tokens":\#(input),"input_tokens_details":{"cached_tokens":\#(cached)},"output_tokens":\#(output),"output_tokens_details":{"reasoning_tokens":\#(reasoning)}}}}"#
    }

    /// A complete stream that responds with the text you specify.
    static func textResponse(_ text: String) -> [String] {
        [created(), itemAdded(0, type: "message"), textDelta(0, text), messageDone(0, text: text), completed()]
    }

    private static func quoted(_ string: String) -> String {
        String(decoding: try! JSONEncoder().encode(string), as: UTF8.self)
    }
}
