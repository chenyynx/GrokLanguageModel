//
//  ServerSentEvents.swift
//  GrokLanguageModel
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation

/// An event from a `text/event-stream` response.
struct ServerSentEvent: Equatable, Sendable {
    var event: String?
    var data: String
}

/// An incremental parser for `text/event-stream` responses.
struct ServerSentEventParser {
    private var line: [UInt8] = []
    private var event: String?
    private var data: [String] = []

    /// Consumes the next byte of the stream, and returns an event if the byte completes one.
    mutating func consume(_ byte: UInt8) -> ServerSentEvent? {
        guard byte == UInt8(ascii: "\n") else {
            line.append(byte)
            return nil
        }
        if line.last == UInt8(ascii: "\r") {
            line.removeLast()
        }
        let text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        return consume(line: text)
    }

    /// Consumes a complete line of the stream, and returns an event if the line completes one.
    mutating func consume(line: String) -> ServerSentEvent? {
        if line.isEmpty {
            return dispatch()
        }
        if line.hasPrefix(":") {
            return nil
        }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") {
                value = value.dropFirst()
            }
        } else {
            field = line[...]
            value = ""
        }
        switch field {
        case "event": event = String(value)
        case "data": data.append(String(value))
        default: break
        }
        return nil
    }

    /// Returns the last event if the stream ended without a trailing blank line.
    mutating func finish() -> ServerSentEvent? {
        if !line.isEmpty {
            let text = String(decoding: line, as: UTF8.self)
            line.removeAll()
            _ = consume(line: text)
        }
        return dispatch()
    }

    private mutating func dispatch() -> ServerSentEvent? {
        defer {
            event = nil
            data.removeAll()
        }
        guard !data.isEmpty else { return nil }
        return ServerSentEvent(event: event, data: data.joined(separator: "\n"))
    }
}
