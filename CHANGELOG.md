# Changelog

All notable changes to GrokLanguageModel are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-09-28

The first release of GrokLanguageModel, which brings SpaceXAI's Grok models to Apple's Foundation Models framework on iOS 27, macOS 27, and visionOS 27.

### Added

- `GrokModel`, a Foundation Models `LanguageModel` that runs Grok models through the xAI Responses API, so you can create a `LanguageModelSession` with `LanguageModelSession(model: GrokModel.grok4)`.
- Model presets: `.grok4` (Grok 4.7), `.grok4_7`, `.grok4_6`, `.grok4_5`, `.grok4_3`, `.grok4_20`, `.grok4_20NonReasoning`, and `.grokBuild`, plus `GrokModel(name:displayName:capabilities:contextSize:supportedReasoningEfforts:reasoningEffort:configuration:)` for models without a preset.
- `GrokModel.presets`, which lists every preset once in an order that suits a model picker, and each model's `displayName` and `supportedReasoningEfforts`, with `supportsReasoningEffort` to check whether a model accepts an effort at all. Models without the `reasoning` capability never send an effort.
- Streaming responses over server-sent events, with snapshots that update as the response arrives.
- Guided generation for `@Generable` types and `GenerationSchema` with strict JSON schemas, including streamed partial results.
- Structured output and tool arguments that generate in the order that your `@Generable` types declare their properties, so streamed snapshots fill in from the first property down.
- Tool calling, including several tool calls in a single turn.
- Reasoning controls with `GrokModel.ReasoningEffort` and the `reasoningEffort(_:)` modifier. A request's `ContextOptions.reasoningLevel` maps to an effort and takes precedence over the model's, and `GrokModel.ReasoningEffort(_:)` performs the same conversion.
- Reasoning summaries recorded as reasoning entries in the transcript, and encrypted reasoning that's sent back to the same model on later turns.
- Image input from `Attachment`, sent as JPEG or PNG data URLs.
- `GrokConfiguration` for the API key, base URL, additional headers, timeout, and URL session, with a thread-safe `GrokConfiguration.default`, `GrokConfiguration.updateDefault(_:)` for atomic changes to it, and an `apiKey(_:)` model modifier.
- A fallback to the `GROK_API_KEY` or `XAI_API_KEY` environment variable when no API key is configured. The fallback only applies to requests to xAI hosts over HTTPS, so a key from the environment is never sent to a custom base URL or in cleartext.
- `GrokConfiguration.apiKeySource` and `GrokConfiguration.APIKeySource`, which tell you whether requests use the configured key, an environment variable, or no key, without exposing the key.
- Support for routing requests through your own server, which doesn't require an API key in the app.
- `GrokError` for request, generation, response, and image-encoding failures, whose cases stay the same throughout 1.x. HTTP 429 responses throw `LanguageModelError.rateLimited`, timeouts throw `LanguageModelError.timeout`, and content-filter stops throw `LanguageModelError.guardrailViolation`.
- Token usage for each response, including cached input tokens and reasoning tokens.
- `GenerationOptions` support for temperature, maximum response tokens, greedy and random sampling, and tool calling modes.
- Requests that use `store: false`, and a per-session `prompt_cache_key` for prompt cache hits.
- Redaction of API keys, header values, and credentials in the base URL from `GrokConfiguration` descriptions and mirrors.
- A DocC documentation catalog.
- Offline tests against a mock server, and live tests against the xAI API.
- Example apps: GrokChat for iOS and GrokStudio for macOS.

[Unreleased]: https://github.com/MarcoDotIO/GrokLanguageModel/compare/1.0.0...HEAD
[1.0.0]: https://github.com/MarcoDotIO/GrokLanguageModel/releases/tag/1.0.0
