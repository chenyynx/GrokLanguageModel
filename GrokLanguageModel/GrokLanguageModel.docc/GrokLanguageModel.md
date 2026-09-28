# ``GrokLanguageModel``

Use SpaceXAI's Grok models, through the xAI API, with the Foundation Models framework.

## Overview

GrokLanguageModel provides ``GrokModel``, a `LanguageModel` that you pass to a
`LanguageModelSession`. Once you create a session, you use the same Foundation
Models API that you use with the on-device system model: prompts and
instructions, streaming, guided generation with `@Generable` types, tool
calling, reasoning, and image attachments.

```swift
import FoundationModels
import GrokLanguageModel

GrokConfiguration.default.apiKey = "<your xAI API key>"

let session = LanguageModelSession(model: GrokModel.grok4)
let response = try await session.respond(to: "What makes a great Swift API?")
print(response.content)
```

Requests go to the xAI Responses API and stream back as server-sent events.
The session keeps the transcript, so the package sends the full conversation
with each request and asks the server not to store it. When a Grok model
reasons, the package records the model's encrypted reasoning in the transcript
and sends it back with later requests to the same model, so the model keeps its
train of thought across turns.

### Provide an API key

Set an API key on ``GrokConfiguration/default`` once, before you create
sessions, or give a single model its own key with ``GrokModel/apiKey(_:)``:

```swift
GrokConfiguration.default.apiKey = "<your xAI API key>"

let model = GrokModel.grok4.apiKey("<your xAI API key>")
```

If no key is configured, requests to the xAI API fall back to the
`GROK_API_KEY` environment variable, then `XAI_API_KEY`, which is convenient
during development and testing. ``GrokModel/apiKey(_:)`` copies
``GrokConfiguration/default`` when you call it, so later changes to the default
configuration don't apply to that model. ``GrokConfiguration/apiKeySource``
tells you which key requests use, without exposing the key itself:

```swift
let keyStatus = switch GrokConfiguration.default.apiKeySource {
case .configuration: "Using the key you entered"
case .environment(let variable): "Using \(variable) from the environment"
case nil: "No API key"
}
```

### Choose a model

``GrokModel/grok4`` is the most capable Grok 4 model, currently Grok 4.7. Use
a versioned preset, like ``GrokModel/grok4_3``, to pin a model:

| Preset | Display name | API model | Context window | Reasoning efforts |
| --- | --- | --- | --- | --- |
| ``GrokModel/grok4_7`` (also ``GrokModel/grok4``) | Grok 4.7 | `grok-4.7` | 500K | `.low`, `.medium`, `.high`, `.xhigh` |
| ``GrokModel/grok4_6`` | Grok 4.6 | `grok-4.6` | 500K | `.low`, `.medium`, `.high`, `.xhigh` |
| ``GrokModel/grok4_5`` | Grok 4.5 | `grok-4.5` | 500K | `.low`, `.medium`, `.high` |
| ``GrokModel/grok4_3`` | Grok 4.3 | `grok-4.3` | 1M | `.disabled`, `.low`, `.medium`, `.high` |
| ``GrokModel/grok4_20`` | Grok 4.20 | `grok-4.20-reasoning` | 1M | Not adjustable |
| ``GrokModel/grok4_20NonReasoning`` | Grok 4.20 Non-Reasoning | `grok-4.20-non-reasoning` | 1M | None (doesn't reason) |
| ``GrokModel/grokBuild`` | Grok Build | `grok-build-0.1` | 256K | Not adjustable |

``GrokModel/presets`` lists every preset once, in an order that suits a model
picker. Each model's ``GrokModel/displayName`` is a name to show people, and
its ``GrokModel/supportedReasoningEfforts`` lists the efforts it accepts:

```swift
import GrokLanguageModel
import SwiftUI

struct ModelPicker: View {
    @Binding var model: GrokModel

    var body: some View {
        Picker("Model", selection: $model) {
            ForEach(GrokModel.presets, id: \.self) { preset in
                Text(preset.displayName).tag(preset)
            }
        }
    }
}
```

To use a model that doesn't have a preset yet, create it by name, and list
the reasoning efforts it accepts, or pass an empty array if it doesn't accept
one. A model whose capabilities don't include `reasoning` accepts no efforts
by default:

```swift
let model = GrokModel(
    name: "grok-4.8",
    displayName: "Grok 4.8",
    contextSize: 500_000,
    supportedReasoningEfforts: [.low, .medium, .high, .xhigh]
)
```

### Control reasoning

Set a default effort on the model with ``GrokModel/reasoningEffort(_:)``, or
set one for a single request with `ContextOptions`:

```swift
let session = LanguageModelSession(model: GrokModel.grok4.reasoningEffort(.low))

let response = try await session.respond(
    to: "Prove that there are infinitely many primes.",
    contextOptions: ContextOptions(reasoningLevel: .deep)
)
print(response.usage.output.reasoningTokenCount)
```

A request's `ContextOptions/reasoningLevel` takes precedence over the model's
``GrokModel/reasoningEffort``. The package maps `.light`, `.moderate`, and
`.deep` to ``GrokModel/ReasoningEffort/low``,
``GrokModel/ReasoningEffort/medium``, and ``GrokModel/ReasoningEffort/high``,
and sends a `.custom(_:)` level's value as is. Models that don't reason, or
whose ``GrokModel/supportedReasoningEfforts`` is empty, have a
``GrokModel/supportsReasoningEffort`` of `false`, and ignore both settings.

The package doesn't check an effort against the model's
``GrokModel/supportedReasoningEfforts``, so only offer efforts the model
accepts. The xAI API rejects some unsupported efforts, and treats
``GrokModel/ReasoningEffort/xhigh`` as ``GrokModel/ReasoningEffort/high`` on
models before Grok 4.6. ``GrokModel/ReasoningEffort/init(_:)`` converts a
reasoning level with the same mapping that the package uses:

```swift
let level = ContextOptions.ReasoningLevel.custom("xhigh")

if GrokModel.grok4_5.supportedReasoningEfforts.contains(GrokModel.ReasoningEffort(level)) {
    // Grok 4.5 doesn't support xhigh, so this doesn't run.
}
```

### Generate structured output

Describe the output you want with a `@Generable` type, and the model fills it
in. The package sends your type's schema as a strict JSON schema, with its
properties in the order that your type declares them. Grok generates them in
that order, so streamed `PartiallyGenerated` snapshots fill in from the first
property down:

```swift
@Generable
struct Itinerary {
    @Guide(description: "A short, catchy title for the trip")
    var title: String

    @Guide(description: "One activity for each day of the trip", .count(1...7))
    var activities: [String]
}

let stream = session.streamResponse(to: "Plan a three-day trip to Japan.", generating: Itinerary.self)

for try await snapshot in stream {
    print(snapshot.content.title ?? "…", snapshot.content.activities?.count ?? 0)
}
```

Tool arguments generate in declaration order too.

### Stream responses

Each snapshot of a streamed response contains the full response so far. To
stop a response early, cancel the task that iterates the stream. The loop ends
without throwing an error:

```swift
let task = Task {
    for try await snapshot in session.streamResponse(to: "Tell me a long story about Mars.") {
        print(snapshot.content)
    }
}

// Later, when someone taps Stop:
task.cancel()
```

### Require tool calls

A `GenerationOptions/toolCallingMode` of `.required` follows Foundation
Models semantics: the session requires a tool call in every request of the
turn, including the follow-up requests that carry tool output, so the model
keeps calling tools until one of them throws an error or a dynamic profile
changes the mode. To require just one call, count tool calls in a
`LanguageModelSession/DynamicProfile`, like this one for an app with a
`WeatherTool`:

```swift
extension SessionPropertyValues {
    @SessionPropertyEntry
    var toolCallCount: Int = 0
}

struct WeatherProfile: LanguageModelSession.DynamicProfile {
    @SessionProperty(\.toolCallCount)
    var toolCallCount

    var body: some LanguageModelSession.DynamicProfile {
        Profile {
            Instructions("Use the getWeather tool to answer questions about the weather.")
            WeatherTool()
        }
        .model(GrokModel.grok4)
        .toolCallingMode(toolCallCount < 1 ? .required : .allowed)
        .onToolCall {
            toolCallCount += 1
        }
    }
}

let session = LanguageModelSession(profile: WeatherProfile())
```

The count lasts for the whole session. To require a tool call again for a
later prompt, reset it first with `session.properties.toolCallCount = 0`.

### Handle errors

Rate limits, timeouts, and content-filter stops surface as
`LanguageModelError.rateLimited`, `.timeout`, and `.guardrailViolation`.
Other API failures throw a ``GrokError``, like
``GrokError/requestFailed(statusCode:code:message:)`` when the xAI API rejects
a request, including one whose conversation doesn't fit in the model's context
window, and connection failures throw the underlying `URLError`.

### Keep your API key safe

An API key that ships inside an app can be extracted from it. In production,
point ``GrokConfiguration/baseURL`` at your own server that authenticates your
users, adds the key, and forwards requests to the xAI API. When the base URL
isn't an xAI host, the package doesn't require an API key and never reads the
`GROK_API_KEY` or `XAI_API_KEY` environment variable, so a key from your
development environment can't reach that server. The package also never sends
a key from the environment over plain HTTP. If you set
``GrokConfiguration/apiKey``, the package still sends it to that server, so
only use base URLs that you trust, over `https`.

## Topics

### Models

- ``GrokModel``
- ``GrokModel/ReasoningEffort``

### Configuration

- ``GrokConfiguration``

### Errors

- ``GrokError``

### Running requests

- ``GrokModel/Executor``
