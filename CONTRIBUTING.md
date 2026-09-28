# Contributing to GrokLanguageModel

Thanks for your interest in improving GrokLanguageModel! Bug reports, model
updates, documentation fixes, and new features are all welcome. This guide
explains how to set up the project, run the tests, and get a change merged.

- **Questions and ideas:** start a thread in [GitHub Discussions](https://github.com/MarcoDotIO/GrokLanguageModel/discussions).
- **Bugs, feature requests, and model updates:** [open an issue](https://github.com/MarcoDotIO/GrokLanguageModel/issues/new/choose) using one of the templates.
- **Security vulnerabilities:** don't open a public issue. Follow [SECURITY.md](SECURITY.md) instead.

## Setting up

You need a Mac running macOS 27 with **Xcode 27.1 or later**, which includes
Swift 6.4 and the iOS 27, macOS 27, and visionOS 27 SDKs.

```bash
git clone https://github.com/MarcoDotIO/GrokLanguageModel.git
cd GrokLanguageModel
```

Then open the project in Xcode, in whichever form you prefer:

- **`Package.swift`**, to work on the package the way Swift Package Manager
  sees it. Choose **File › Open** in Xcode and select `Package.swift`.
- **`GrokLanguageModel.xcodeproj`**, which builds the same sources as a
  framework, and is what CI uses for the iOS and visionOS builds.

Both use the same source folders, so changes show up in each. To work from the
command line instead, use `swift build` and `swift test`.

`GrokLanguageModel.xcodeproj` and the GrokStudio example don't set a
development team, so Xcode signs their builds to run locally, which is all
that the tests and the Mac app need. To run GrokChat on a device, choose your
own team under **Signing & Capabilities**, and don't commit that change.

### Project layout

| Path | Contents |
| --- | --- |
| `GrokLanguageModel/` | The package sources and the DocC catalog. |
| `GrokLanguageModelTests/` | Offline tests that use a mock server, and live tests that call the xAI API. |
| `Examples/` | The GrokChat (iOS) and GrokStudio (macOS) example apps, which use the package through a local package reference. |
| `.github/` | CI and release workflows, and the issue and pull request templates. |

The main source files are:

| File | Responsibility |
| --- | --- |
| `GrokModel.swift` | The public model type, its presets, and its modifiers. |
| `GrokConfiguration.swift` | Connection settings, API key resolution, and building the URL request. |
| `GrokModel+Executor.swift` | The `LanguageModelExecutor` that sends requests and streams responses. |
| `ResponsesRequest.swift` | Encoding a Foundation Models request and transcript as a Responses API request. |
| `JSONValue.swift` | A JSON value type for schemas and error bodies, and the ordered JSON writer that serializes request bodies, keeping schema properties in the order that `@Generable` types declare them. |
| `ResponseStream.swift` | Translating Responses API stream events into generation channel events. |
| `ServerSentEvents.swift` | Parsing server-sent events. |
| `ImageEncoder.swift` | Encoding image attachments as data URLs. |
| `GrokError.swift` | Errors, and mapping HTTP failures to errors. |

## Running the tests

The test suite has two parts:

- **Offline tests** run against a mock server, need no API key, and never touch
  the network. They cover request encoding and JSON writing, stream
  translation, configuration, and end-to-end sessions.
- **Live tests**, the `GrokLanguageModelTests` suite in
  `GrokLanguageModelTests.swift`, send a few small requests to the xAI API.
  They run only when an API key is available, and they use your xAI
  account's credits.

```bash
# All tests. Without an API key, the live tests are skipped.
swift test

# Offline tests only.
swift test --skip GrokLanguageModelTests.GrokLanguageModelTests/

# Live tests only.
swift test --filter GrokLanguageModelTests.GrokLanguageModelTests/
```

To run the live tests, set `GROK_API_KEY` (or `XAI_API_KEY`) in your
environment, or set `GROK_API_KEY` in a `.env` file at the root of the
repository:

```dotenv
GROK_API_KEY=<your xAI API key>
```

`.env` is listed in `.gitignore`. Never commit it, and never paste a key into
an issue, a pull request, a test fixture, or a screenshot. To keep other
accounts on your Mac from reading it, run `chmod 600 .env`.

You can also run the tests in Xcode with **Product › Test**.

> [!NOTE]
> Pull requests, including ones from forks, can't access the project's API key.
> CI runs the offline tests on every pull request. Maintainers run the live
> tests in CI through the `grok-api` environment, which holds the
> `GROK_API_KEY` secret and is only available to the `main` branch and version
> tags. If your change affects how the package talks to the xAI API, run the
> live tests with your own key and say so in your pull request.

## Code style

Match the style of the surrounding code. In particular:

- **Swift 6.** The package builds in the Swift 6 language mode with strict
  concurrency checking, plus the upcoming features that `Package.swift`
  enables. Public types are `Sendable`.
- **No dependencies.** The package uses only Apple's frameworks.
- **Zero warnings.** Changes must build without warnings in both Swift Package
  Manager and Xcode, and CI treats Swift warnings as errors. You can check with
  `swift build -Xswiftc -warnings-as-errors`.
- **Documentation comments.** Document every public symbol with an
  Apple-style doc comment: a one-sentence summary, then details, parameters,
  and a code sample when it helps. Link to other symbols with double
  backticks, like ` ``GrokConfiguration/default`` `.
- **File headers.** New files start with the same header as the existing
  sources:

  ```swift
  //
  //  FileName.swift
  //  GrokLanguageModel
  //
  //  Created by Your Name on 9/28/26.
  //
  ```

- **Tests.** Cover new behavior with offline tests that use `MockServer`, so
  they run in CI for every pull request. Add a live test only for behavior
  that a mock can't show, and keep its requests small.
- **Docs.** When you change public API or behavior, update the README, the DocC
  catalog in `GrokLanguageModel/GrokLanguageModel.docc`, and, if needed, the
  example apps.

## Adding a model preset

When xAI releases a model or changes an existing one:

1. Add a `static let` to the `Presets` section of
   `GrokLanguageModel/GrokModel.swift`, with a doc comment that describes the
   model. Set its API `name`, its `displayName`, and its `contextSize`, and
   list the efforts it accepts in `supportedReasoningEfforts`, from least to
   most, or pass an empty array if the model doesn't accept a reasoning
   effort. Pass `capabilities` without `.reasoning` if the model doesn't
   reason, and without `.vision` if it doesn't accept images.
2. Add the preset to `presets`, in the position where it belongs in a model
   picker.
3. If the new model supersedes the most capable Grok 4 model, update `grok4`
   to return it.
4. If the model changes which reasoning efforts are available, update the
   `ReasoningEffort` documentation.
5. Update the preset expectations in the `GrokModelTests` suite in
   `ConfigurationTests.swift`, and in `PublicAPITests.swift`. Add offline
   tests for anything else that's model-specific, like whether requests
   include a reasoning effort. See `RequestTests.swift` for examples.
6. Add the preset to the **Models** tables in `README.md` and the DocC
   landing page, and add an entry to `CHANGELOG.md`.

Check the model's name, context window, and reasoning options against the
[xAI documentation](https://docs.x.ai).

## Submitting a pull request

1. Fork the repository and create a branch from `main`.
2. Make your change, with tests and documentation.
3. Run `swift test`, and make sure the build has no warnings. If you changed
   anything the example apps use, build them too.
4. Add an entry under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md), in the
   **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, or
   **Security** group.
5. Open a pull request and fill out the template.

Keep each pull request focused on one change. CI must pass before a pull
request is merged. It runs the offline tests on macOS and in the iOS
Simulator, builds the package for iOS and visionOS, and builds both example
apps.

## Releases

Maintainers publish releases. To cut one, move the `[Unreleased]` entries in
`CHANGELOG.md` under a new version heading, update the links at the bottom of
the file, and push a tag named after the version, with no `v` prefix, like
`1.1.0`, that points to a commit on `main`. The Release workflow checks that
the tagged commit is on `main`, runs the offline and live tests, then
publishes a GitHub release with that version's changelog entry as its notes.

## License

By contributing, you agree that your contributions are licensed under the
[MIT license](LICENSE) that covers the project.
