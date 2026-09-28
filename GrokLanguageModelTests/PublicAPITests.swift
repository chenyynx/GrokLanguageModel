//
//  PublicAPITests.swift
//  GrokLanguageModelTests
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels
import GrokLanguageModel
import Testing

/// Tests that only use the package's public API.
///
/// This file imports the package without `@testable`, so it doesn't compile
/// if a declaration that apps use isn't public.
struct PublicAPITests {
    @Test func createsModelsWithEveryInitializerParameter() {
        let model = GrokModel(
            name: "grok-4.8",
            displayName: "Grok 4.8",
            capabilities: [.guidedGeneration, .toolCalling, .reasoning],
            contextSize: 128_000,
            supportedReasoningEfforts: [.low, .high],
            reasoningEffort: .high,
            configuration: GrokConfiguration(apiKey: "key")
        )

        #expect(model.name == "grok-4.8")
        #expect(model.displayName == "Grok 4.8")
        #expect(model.contextSize == 128_000)
        #expect(model.supportedReasoningEfforts == [.low, .high])
        #expect(model.supportsReasoningEffort)
        #expect(model.reasoningEffort == .high)
        #expect(!model.capabilities.contains(.vision))
        #expect(model.configuration?.apiKeySource == .configuration)
        #expect(!GrokModel(name: "grok-custom", capabilities: [.toolCalling]).supportsReasoningEffort)
    }

    @Test func describesPresetsForAModelPicker() {
        let reasoningModels = GrokModel.presets.filter(\.supportsReasoningEffort)

        #expect(GrokModel.presets.count == 7)
        #expect(GrokModel.presets.first?.displayName == "Grok 4.7")
        #expect(GrokModel.presets.first?.supportedReasoningEfforts.map(\.rawValue) == ["low", "medium", "high", "xhigh"])
        #expect(reasoningModels.map(\.displayName) == ["Grok 4.7", "Grok 4.6", "Grok 4.5", "Grok 4.3"])
    }

    @Test func mapsReasoningLevelsToEfforts() {
        #expect(GrokModel.ReasoningEffort(.light) == .low)
        #expect(GrokModel.ReasoningEffort(.moderate) == .medium)
        #expect(GrokModel.ReasoningEffort(.deep) == .high)
        #expect(GrokModel.ReasoningEffort(.custom("xhigh")) == .xhigh)
    }

    @Test func reportsAPIKeySources() throws {
        let proxy = try #require(URL(string: "https://proxy.example.com/grok/v1"))
        let source: GrokConfiguration.APIKeySource = .environment(variable: "GROK_API_KEY")

        #expect(GrokConfiguration(baseURL: proxy).apiKeySource == nil)
        #expect(GrokConfiguration(apiKey: "key", baseURL: proxy).apiKeySource == .configuration)
        guard case .environment(let variable) = source else {
            Issue.record("Expected an environment variable source")
            return
        }
        #expect(variable == "GROK_API_KEY")
    }
}
