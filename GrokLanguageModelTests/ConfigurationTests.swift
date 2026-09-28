//
//  ConfigurationTests.swift
//  GrokLanguageModelTests
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels
import Testing
@testable import GrokLanguageModel

struct ConfigurationTests {
    @Test func resolvesAPIKeysInOrder() {
        let environment = ["GROK_API_KEY": "grok-env", "XAI_API_KEY": "xai-env"]

        let explicit = GrokConfiguration(apiKey: "explicit").resolvedAPIKey(environment: environment)
        #expect(explicit?.key == "explicit")
        #expect(explicit?.source == .configuration)

        let grok = GrokConfiguration(apiKey: "").resolvedAPIKey(environment: environment)
        #expect(grok?.key == "grok-env")
        #expect(grok?.source == .environment(variable: "GROK_API_KEY"))

        let xAI = GrokConfiguration().resolvedAPIKey(environment: ["GROK_API_KEY": "", "XAI_API_KEY": "xai-env"])
        #expect(xAI?.key == "xai-env")
        #expect(xAI?.source == .environment(variable: "XAI_API_KEY"))

        #expect(GrokConfiguration().resolvedAPIKey(environment: [:]) == nil)
    }

    @Test func reportsTheAPIKeySource() throws {
        let proxy = try #require(URL(string: "https://proxy.example.com/grok/v1"))

        #expect(GrokConfiguration(apiKey: "explicit").apiKeySource == .configuration)
        #expect(GrokConfiguration(apiKey: "explicit", baseURL: proxy).apiKeySource == .configuration)
        // Requests to other hosts never read the environment, so this doesn't
        // depend on the environment that the tests run in.
        #expect(GrokConfiguration(baseURL: proxy).apiKeySource == nil)
        // Without a key, the source comes from the process environment, like
        // the key for a request does.
        let environment = ProcessInfo.processInfo.environment
        #expect(GrokConfiguration().apiKeySource == GrokConfiguration().resolvedAPIKey(environment: environment)?.source)
    }

    @Test func usesEnvironmentKeysForXAIRequests() throws {
        let environment = ["GROK_API_KEY": "grok-env", "XAI_API_KEY": "xai-env"]
        let regional = try #require(URL(string: "https://us-east-1.api.x.ai/v1"))
        let uppercase = try #require(URL(string: "https://API.X.AI/v1"))

        let request = try GrokConfiguration().makeURLRequest(body: [String: String](), environment: environment)
        let regionalRequest = try GrokConfiguration(baseURL: regional).makeURLRequest(
            body: [String: String](),
            environment: ["XAI_API_KEY": "xai-env"]
        )
        let uppercaseRequest = try GrokConfiguration(baseURL: uppercase).makeURLRequest(body: [String: String](), environment: environment)

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer grok-env")
        #expect(regionalRequest.value(forHTTPHeaderField: "Authorization") == "Bearer xai-env")
        #expect(uppercaseRequest.value(forHTTPHeaderField: "Authorization") == "Bearer grok-env")
    }

    @Test(arguments: [
        "https://proxy.example.com/grok/v1",
        "https://api.x.ai.example.com/v1",
        "https://api.x.ai@evil.example.com/v1",
        "https://evil.example.com/api.x.ai/v1",
        "https://notx.ai/v1",
        "http://localhost:8080/v1",
    ])
    func doesNotSendEnvironmentKeysToOtherHosts(baseURL: String) throws {
        let url = try #require(URL(string: baseURL))
        let environment = ["GROK_API_KEY": "grok-env", "XAI_API_KEY": "xai-env"]
        let configuration = GrokConfiguration(baseURL: url)

        let request = try configuration.makeURLRequest(body: [String: String](), environment: environment)

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(configuration.resolvedAPIKey(environment: environment) == nil)
        #expect(configuration.apiKeySource == nil)
    }

    @Test func doesNotSendEnvironmentKeysOverHTTP() throws {
        let url = try #require(URL(string: "http://api.x.ai/v1"))
        let environment = ["GROK_API_KEY": "grok-env", "XAI_API_KEY": "xai-env"]
        let configuration = GrokConfiguration(baseURL: url)

        #expect(configuration.resolvedAPIKey(environment: environment) == nil)
        #expect(configuration.apiKeySource == nil)
        // The xAI API requires a key, so the request fails instead of going
        // out without one.
        #expect(throws: GrokError.self) {
            try configuration.makeURLRequest(body: [String: String](), environment: environment)
        }
    }

    @Test func sendsAnExplicitKeyToOtherHosts() throws {
        let proxy = try #require(URL(string: "https://proxy.example.com/grok/v1"))
        let configuration = GrokConfiguration(apiKey: "proxy-key", baseURL: proxy)

        let request = try configuration.makeURLRequest(body: [String: String](), environment: ["GROK_API_KEY": "grok-env"])

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer proxy-key")
        #expect(configuration.apiKeySource == .configuration)
    }

    @Test func buildsAuthenticatedRequests() throws {
        let configuration = GrokConfiguration(apiKey: "secret", additionalHeaders: ["X-Trace": "1"], timeoutInterval: 30)

        let request = try configuration.makeURLRequest(body: ["hello": "world"], environment: [:])

        #expect(request.url?.absoluteString == "https://api.x.ai/v1/responses")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 30)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Trace") == "1")
        #expect(request.httpBody == Data(#"{"hello":"world"}"#.utf8))
    }

    @Test func requiresAnAPIKeyForXAI() {
        #expect(throws: GrokError.self) {
            try GrokConfiguration().makeURLRequest(body: [String: String](), environment: [:])
        }
    }

    @Test func allowsProxiesWithoutAnAPIKey() throws {
        let proxy = try #require(URL(string: "https://proxy.example.com/grok/v1"))

        let request = try GrokConfiguration(baseURL: proxy).makeURLRequest(body: [String: String](), environment: [:])

        #expect(request.url?.absoluteString == "https://proxy.example.com/grok/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func comparesURLSessionsByIdentity() {
        let session = URLSession(configuration: .ephemeral)

        #expect(GrokConfiguration(urlSession: session) == GrokConfiguration(urlSession: session))
        #expect(GrokConfiguration(urlSession: session) != GrokConfiguration(urlSession: URLSession(configuration: .ephemeral)))
    }

    @Test func redactsSecretsFromDescriptions() {
        let configuration = GrokConfiguration(apiKey: "xai-secret", additionalHeaders: ["X-Proxy-Token": "token-secret"])
        var dumped = ""
        dump(configuration, to: &dumped)

        for output in [configuration.description, configuration.debugDescription, String(reflecting: configuration), dumped] {
            #expect(!output.contains("xai-secret"))
            #expect(!output.contains("token-secret"))
        }
    }

    @Test func redactsCredentialsInTheBaseURL() throws {
        let url = try #require(URL(string: "https://user:url-secret@proxy.example.com/v1?token=query-secret#fragment-secret"))
        let configuration = GrokConfiguration(apiKey: "key-secret", baseURL: url)
        var model = GrokModel.grok4_3
        model.configuration = configuration
        var dumped = ""
        dump(configuration, to: &dumped)

        for output in [configuration.description, String(reflecting: configuration), dumped, String(describing: model), String(reflecting: model)] {
            #expect(!output.contains("secret"))
            #expect(!output.contains("user:"))
        }
        #expect(configuration.description.contains("https://<redacted>@proxy.example.com/v1?<redacted>#<redacted>"))
        #expect(GrokConfiguration().description.contains("baseURL: https://api.x.ai/v1,"))
    }

    @Test func updatesTheDefaultConfigurationAtomically() async {
        let original = GrokConfiguration.default.timeoutInterval
        defer { GrokConfiguration.updateDefault { $0.timeoutInterval = original } }
        let updates = 1_000

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<updates {
                group.addTask { @concurrent in
                    GrokConfiguration.updateDefault { $0.timeoutInterval += 1 }
                }
            }
        }

        #expect(GrokConfiguration.default.timeoutInterval == original + Double(updates))
    }

    @Test func extractsErrorDetails() {
        let xAIStyle = GrokError.errorDetails(in: Data(#"{"code":"invalid-argument","error":"Bad model"}"#.utf8))
        let openAIStyle = GrokError.errorDetails(in: Data(#"{"error":{"code":401,"message":"Unauthorized"}}"#.utf8))
        let plainText = GrokError.errorDetails(in: Data("Service Unavailable".utf8))

        #expect(xAIStyle.code == "invalid-argument" && xAIStyle.message == "Bad model")
        #expect(openAIStyle.code == "401" && openAIStyle.message == "Unauthorized")
        #expect(plainText.code == nil && plainText.message == "Service Unavailable")
    }
}

struct GrokModelTests {
    @Test func grok4IsTheLatestGrok4Model() {
        #expect(GrokModel.grok4 == GrokModel.grok4_7)
        #expect(GrokModel.grok4.name == "grok-4.7")
    }

    @Test func listsPresetsInOrder() {
        #expect(GrokModel.presets == [
            .grok4_7, .grok4_6, .grok4_5, .grok4_3, .grok4_20, .grok4_20NonReasoning, .grokBuild,
        ])
        #expect(GrokModel.presets.map(\.name) == [
            "grok-4.7", "grok-4.6", "grok-4.5", "grok-4.3",
            "grok-4.20-reasoning", "grok-4.20-non-reasoning", "grok-build-0.1",
        ])
        #expect(GrokModel.presets.map(\.displayName) == [
            "Grok 4.7", "Grok 4.6", "Grok 4.5", "Grok 4.3",
            "Grok 4.20", "Grok 4.20 Non-Reasoning", "Grok Build",
        ])
        #expect(GrokModel.presets.map(\.contextSize) == [
            500_000, 500_000, 500_000, 1_000_000, 1_000_000, 1_000_000, 256_000,
        ])
        #expect(GrokModel.presets.allSatisfy { $0.reasoningEffort == nil && $0.configuration == nil })
    }

    @Test(arguments: [
        (GrokModel.grok4_7, [GrokModel.ReasoningEffort.low, .medium, .high, .xhigh]),
        (.grok4_6, [.low, .medium, .high, .xhigh]),
        (.grok4_5, [.low, .medium, .high]),
        (.grok4_3, [.disabled, .low, .medium, .high]),
        (.grok4_20, []),
        (.grok4_20NonReasoning, []),
        (.grokBuild, []),
    ])
    func declaresSupportedReasoningEfforts(model: GrokModel, efforts: [GrokModel.ReasoningEffort]) {
        #expect(model.supportedReasoningEfforts == efforts)
        #expect(model.supportsReasoningEffort == !efforts.isEmpty)
    }

    @Test func derivesReasoningEffortSupportFromSupportedEfforts() {
        var model = GrokModel(name: "grok-test", supportedReasoningEfforts: [])
        #expect(!model.supportsReasoningEffort)

        model.supportedReasoningEfforts = [.high]
        #expect(model.supportsReasoningEffort)

        model.supportedReasoningEfforts.removeAll()
        #expect(!model.supportsReasoningEffort)
    }

    @Test func acceptsNoEffortsByDefaultWithoutReasoning() {
        let model = GrokModel(name: "grok-custom", capabilities: [.vision, .guidedGeneration, .toolCalling])
        #expect(model.supportedReasoningEfforts.isEmpty)
        #expect(!model.supportsReasoningEffort)

        // A model that doesn't reason never accepts an effort, even one it lists.
        let listed = GrokModel(name: "grok-custom", capabilities: [.toolCalling], supportedReasoningEfforts: [.low])
        #expect(listed.supportedReasoningEfforts == [.low])
        #expect(!listed.supportsReasoningEffort)
    }

    @Test func usesDefaultsForCustomModels() {
        let model = GrokModel(name: "grok-4.8")

        #expect(model.name == "grok-4.8")
        #expect(model.displayName == "grok-4.8")
        #expect(model.contextSize == 256_000)
        #expect(model.supportedReasoningEfforts == [.low, .medium, .high])
        #expect(model.supportsReasoningEffort)
        #expect(model.reasoningEffort == nil)
        #expect(model.configuration == nil)
        for capability in [LanguageModelCapabilities.Capability.vision, .guidedGeneration, .toolCalling, .reasoning] {
            #expect(model.capabilities.contains(capability))
        }

        let named = GrokModel(name: "grok-4.8", displayName: "Grok 4.8")
        #expect(named.displayName == "Grok 4.8")
        #expect(named != model)
    }

    @Test func declaresCapabilities() {
        #expect(GrokModel.grok4.capabilities.contains(.reasoning))
        #expect(GrokModel.grok4.capabilities.contains(.toolCalling))
        #expect(GrokModel.grok4.capabilities.contains(.guidedGeneration))
        #expect(GrokModel.grok4.capabilities.contains(.vision))
        #expect(!GrokModel.grok4_20NonReasoning.capabilities.contains(.reasoning))
        #expect(!GrokModel.grok4_20.supportsReasoningEffort)
        #expect(!GrokModel.grokBuild.supportsReasoningEffort)
    }

    @Test func appliesModifiers() {
        let model = GrokModel.grok4_3.reasoningEffort(.disabled).apiKey("key")

        #expect(model.reasoningEffort?.rawValue == "none")
        #expect(model.configuration?.apiKey == "key")
        #expect(model.executorConfiguration.apiKey == "key")
        #expect(GrokModel.grok4_3.configuration == nil)
    }

    @Test(arguments: [
        (ContextOptions.ReasoningLevel.light, "low"),
        (.moderate, "medium"),
        (.deep, "high"),
        (.custom("xhigh"), "xhigh"),
    ])
    func mapsReasoningLevels(level: ContextOptions.ReasoningLevel, effort: String) {
        #expect(GrokModel.ReasoningEffort(level).rawValue == effort)
    }
}
