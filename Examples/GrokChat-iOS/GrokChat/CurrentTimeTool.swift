//
//  CurrentTimeTool.swift
//  GrokChat
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels

/// A tool that looks up the current date and time on the device.
///
/// Language models don't know what time it is, so Grok calls this tool to
/// answer questions like "What time is it in Tokyo?" The app shows a chip
/// under each reply that used it.
nonisolated struct CurrentTimeTool: Tool {
    let name = "getCurrentTime"
    let description = """
        Gets the current date and time on the user's device, in the device's time zone \
        or in a time zone you specify.
        """

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "An IANA time zone identifier, like Asia/Tokyo. Omit it to use the device's time zone.")
        var timeZone: String?
    }

    @concurrent func call(arguments: Arguments) async throws -> String {
        let requestedTimeZone = arguments.timeZone.flatMap(TimeZone.init(identifier:))
        let timeZone = requestedTimeZone ?? .current
        let now = Date.now
        let readable = now.formatted(Date.FormatStyle(date: .complete, time: .complete, timeZone: timeZone))
        let iso8601 = now.ISO8601Format(.iso8601(timeZone: timeZone))

        var result = "It's \(readable) (\(iso8601)) in the \(timeZone.identifier) time zone."
        if let identifier = arguments.timeZone, requestedTimeZone == nil {
            result += " \"\(identifier)\" isn't a known time zone, so this is the device's time zone."
        }
        return result
    }
}
