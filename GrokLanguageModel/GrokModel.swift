//
//  GrokModel.swift
//  GrokLanguageModel
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import FoundationModels

/// A SpaceXAI Grok model that you can use with a `LanguageModelSession`.
///
/// Pass a Grok model to any `LanguageModelSession` initializer that accepts a
/// `LanguageModel`, then use the same Foundation Models API you use with the
/// on-device system model:
///
/// ```swift
/// import FoundationModels
/// import GrokLanguageModel
///
/// GrokConfiguration.default.apiKey = "<your xAI API key>"
///
/// let session = LanguageModelSession(model: GrokModel.grok4)
/// let response = try await session.respond(to: "Tell me a joke!")
/// ```
///
/// Grok models support streaming, guided generation with `@Generable` types,
/// tool calling, reasoning, and image input.
public struct GrokModel: Sendable, Hashable {
    /// The model identifier that the xAI API uses, like `grok-4.7`.
    public var name: String

    /// The name of the model to show people, like `Grok 4.7`.
    public var displayName: String

    /// The maximum number of tokens the model's context window holds.
    ///
    /// This value is informational, like for showing in a model picker. The
    /// package doesn't check requests against it, and when a conversation
    /// outgrows the model's context window, the xAI API rejects the request
    /// with a ``GrokError/requestFailed(statusCode:code:message:)`` error.
    public var contextSize: Int

    /// The reasoning efforts the model accepts, from least to most. Empty when
    /// the model doesn't accept a reasoning effort.
    public var supportedReasoningEfforts: [ReasoningEffort]

    /// A Boolean value that indicates whether the model accepts a reasoning effort.
    ///
    /// This is `true` when the model has the `reasoning` capability and
    /// ``supportedReasoningEfforts`` isn't empty. When it's `false`, requests
    /// don't send ``reasoningEffort`` or a prompt's
    /// `ContextOptions/reasoningLevel` to the API.
    public var supportsReasoningEffort: Bool {
        supportedCapabilities.contains(.reasoning) && !supportedReasoningEfforts.isEmpty
    }

    /// The reasoning effort to request when a prompt doesn't set a
    /// `ContextOptions/reasoningLevel`.
    ///
    /// When this is `nil`, the model uses its default effort.
    public var reasoningEffort: ReasoningEffort?

    /// The connection settings for the model, or `nil` to use
    /// ``GrokConfiguration/default``.
    public var configuration: GrokConfiguration?

    private var supportedCapabilities: Set<LanguageModelCapabilities.Capability>

    /// Creates a Grok model.
    ///
    /// Use this initializer for models that don't have a preset, like newly
    /// released ones.
    ///
    /// - Parameters:
    ///   - name: The model identifier that the xAI API uses.
    ///   - displayName: The name of the model to show people, or `nil` to use `name`.
    ///   - capabilities: The capabilities that the model supports.
    ///   - contextSize: The maximum number of tokens the model's context window holds.
    ///   - supportedReasoningEfforts: The reasoning efforts the model accepts, from
    ///     least to most. Pass an empty array if the model doesn't accept a reasoning
    ///     effort, or `nil` to accept ``ReasoningEffort/low``, ``ReasoningEffort/medium``,
    ///     and ``ReasoningEffort/high`` when `capabilities` includes `reasoning`, and no
    ///     efforts otherwise.
    ///   - reasoningEffort: The reasoning effort to request when a prompt doesn't set one.
    ///   - configuration: The connection settings for the model, or `nil` to use
    ///     ``GrokConfiguration/default``.
    public init(
        name: String,
        displayName: String? = nil,
        capabilities: Set<LanguageModelCapabilities.Capability> = [.vision, .guidedGeneration, .toolCalling, .reasoning],
        contextSize: Int = 256_000,
        supportedReasoningEfforts: [ReasoningEffort]? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        configuration: GrokConfiguration? = nil
    ) {
        self.name = name
        self.displayName = displayName ?? name
        self.supportedCapabilities = capabilities
        self.contextSize = contextSize
        self.supportedReasoningEfforts = supportedReasoningEfforts
            ?? (capabilities.contains(.reasoning) ? [.low, .medium, .high] : [])
        self.reasoningEffort = reasoningEffort
        self.configuration = configuration
    }
}

// MARK: - Presets

extension GrokModel {
    /// The most capable Grok 4 model, currently Grok 4.7.
    public static var grok4: GrokModel { grok4_7 }

    /// Grok 4.7, SpaceXAI's frontier model for coding, agentic tasks, and knowledge work.
    public static let grok4_7 = GrokModel(
        name: "grok-4.7",
        displayName: "Grok 4.7",
        contextSize: 500_000,
        supportedReasoningEfforts: [.low, .medium, .high, .xhigh]
    )

    /// Grok 4.6.
    public static let grok4_6 = GrokModel(
        name: "grok-4.6",
        displayName: "Grok 4.6",
        contextSize: 500_000,
        supportedReasoningEfforts: [.low, .medium, .high, .xhigh]
    )

    /// Grok 4.5.
    public static let grok4_5 = GrokModel(
        name: "grok-4.5",
        displayName: "Grok 4.5",
        contextSize: 500_000,
        supportedReasoningEfforts: [.low, .medium, .high]
    )

    /// Grok 4.3, a fast model with a 1M-token context window that can disable reasoning.
    public static let grok4_3 = GrokModel(
        name: "grok-4.3",
        displayName: "Grok 4.3",
        contextSize: 1_000_000,
        supportedReasoningEfforts: [.disabled, .low, .medium, .high]
    )

    /// The reasoning variant of Grok 4.20.
    public static let grok4_20 = GrokModel(
        name: "grok-4.20-reasoning",
        displayName: "Grok 4.20",
        contextSize: 1_000_000,
        supportedReasoningEfforts: []
    )

    /// The non-reasoning variant of Grok 4.20.
    public static let grok4_20NonReasoning = GrokModel(
        name: "grok-4.20-non-reasoning",
        displayName: "Grok 4.20 Non-Reasoning",
        capabilities: [.vision, .guidedGeneration, .toolCalling],
        contextSize: 1_000_000,
        supportedReasoningEfforts: []
    )

    /// Grok Build 0.1, a model for agentic coding.
    ///
    /// This preset pins `grok-build-0.1`, which replaced `grok-code-fast-1`.
    /// Unlike xAI's `grok-build-latest` alias, which can point to a different
    /// model, it always uses `grok-build-0.1`.
    public static let grokBuild = GrokModel(
        name: "grok-build-0.1",
        displayName: "Grok Build",
        contextSize: 256_000,
        supportedReasoningEfforts: []
    )

    /// Every Grok model preset, in an order that suits a model picker.
    ///
    /// The list includes each model once, so it doesn't include ``grok4``,
    /// which is the same model as ``grok4_7``.
    public static var presets: [GrokModel] {
        [grok4_7, grok4_6, grok4_5, grok4_3, grok4_20, grok4_20NonReasoning, grokBuild]
    }
}

// MARK: - Modifiers

extension GrokModel {
    /// Returns a copy of the model that requests the reasoning effort you specify.
    public func reasoningEffort(_ effort: ReasoningEffort?) -> GrokModel {
        var model = self
        model.reasoningEffort = effort
        return model
    }

    /// Returns a copy of the model that authenticates with the API key you specify.
    ///
    /// The copy uses ``configuration`` if the model has one, or a copy of
    /// ``GrokConfiguration/default`` otherwise. Because it copies the default
    /// configuration when you call this method, later changes to
    /// ``GrokConfiguration/default`` don't apply to the returned model.
    public func apiKey(_ apiKey: String) -> GrokModel {
        var model = self
        var configuration = self.configuration ?? .default
        configuration.apiKey = apiKey
        model.configuration = configuration
        return model
    }
}

// MARK: - LanguageModel

extension GrokModel: LanguageModel {
    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities(Array(supportedCapabilities))
    }

    public var executorConfiguration: GrokConfiguration {
        configuration ?? .default
    }
}

// MARK: - Reasoning effort

extension GrokModel {
    /// How much a Grok model thinks before it responds.
    ///
    /// Supported values depend on the model, and a model's
    /// ``GrokModel/supportedReasoningEfforts`` lists the ones it accepts. For
    /// example, only Grok 4.3 can disable reasoning, and only Grok 4.6 and
    /// later support ``xhigh``; the xAI API treats ``xhigh`` as ``high`` on
    /// earlier models. Some models, like Grok 4.20 and Grok Build, don't
    /// accept a reasoning effort at all.
    public struct ReasoningEffort: RawRepresentable, Hashable, Sendable {
        public var rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// No reasoning.
        public static let disabled = ReasoningEffort(rawValue: "none")

        /// A small amount of reasoning, for latency-sensitive requests.
        public static let low = ReasoningEffort(rawValue: "low")

        /// A moderate amount of reasoning.
        public static let medium = ReasoningEffort(rawValue: "medium")

        /// A large amount of reasoning, for hard problems.
        public static let high = ReasoningEffort(rawValue: "high")

        /// The maximum amount of reasoning.
        public static let xhigh = ReasoningEffort(rawValue: "xhigh")

        /// Creates the reasoning effort that corresponds to a Foundation Models
        /// reasoning level.
        ///
        /// The `light`, `moderate`, and `deep` levels map to ``low``,
        /// ``medium``, and ``high``, and a `custom(_:)` level's value becomes
        /// the effort's raw value as is. Levels that later versions of the
        /// framework add map to ``medium``. This is the mapping that Grok
        /// models use for a request's `ContextOptions/reasoningLevel`.
        ///
        /// - Parameter level: A reasoning level from `ContextOptions`.
        public init(_ level: ContextOptions.ReasoningLevel) {
            switch level {
            case .light: self = .low
            case .moderate: self = .medium
            case .deep: self = .high
            case .custom(let value): self.init(rawValue: value)
            @unknown default: self = .medium
            }
        }
    }
}
