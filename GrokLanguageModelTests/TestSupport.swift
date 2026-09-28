//
//  TestSupport.swift
//  GrokLanguageModelTests
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
@testable import GrokLanguageModel

enum TestSupport {
    /// The API key for live tests, from the `GROK_API_KEY` or `XAI_API_KEY`
    /// environment variable, or from `GROK_API_KEY` in the `.env` file at the
    /// root of the package.
    static let apiKey: String? = {
        let environment = ProcessInfo.processInfo.environment
        if let key = environment["GROK_API_KEY"] ?? environment["XAI_API_KEY"], !key.isEmpty {
            return key
        }
        let envFile = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".env")
        guard let contents = try? String(contentsOf: envFile, encoding: .utf8) else { return nil }
        for line in contents.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "GROK_API_KEY" {
                return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }()

    static var hasAPIKey: Bool { apiKey != nil }

    /// A fast, inexpensive model for live tests.
    static var fastModel: GrokModel {
        GrokModel.grok4_3.reasoningEffort(.low).apiKey(apiKey ?? "")
    }
}
