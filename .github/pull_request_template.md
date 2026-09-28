<!--
Thanks for contributing to GrokLanguageModel!
Please fill out the sections below, and never include an API key or other secret in code, logs, or screenshots.
-->

## Summary

<!-- What does this pull request change, and why? -->

## Related issue

<!-- Link the issue this resolves, like "Closes #123", or "Refs #123" if it only partly addresses it. -->

## Type of change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Model support (a new or updated `GrokModel` preset)
- [ ] Breaking change (changes existing public API or behavior)
- [ ] Documentation (README, DocC, or example apps only)
- [ ] Tests, CI, or tooling
- [ ] Refactoring (no change in behavior)

## How was this tested?

<!-- Describe how you verified the change: tests you added, devices or simulators, OS and Xcode versions. -->

- [ ] `swift test` passes locally (the live tests also run if `GROK_API_KEY` or `XAI_API_KEY` is set, or if a `.env` file at the package root sets `GROK_API_KEY`; to run only the offline tests, use `swift test --skip GrokLanguageModelTests.GrokLanguageModelTests/`)
- [ ] I added or updated offline tests that cover this change
- [ ] I ran the live tests with my own key: `swift test --filter GrokLanguageModelTests.GrokLanguageModelTests/` (optional)

> [!NOTE]
> The live API tests need the `GROK_API_KEY` secret from the `grok-api` environment, which isn't available to pull requests. CI runs the offline tests on every pull request, and maintainers run the live tests through CI on `main` after merging.

## Checklist

- [ ] New and changed public API has doc comments, and the README and DocC catalog are updated where relevant
- [ ] `CHANGELOG.md` is updated under `[Unreleased]`
- [ ] The example apps still build (`GrokChat` for iOS and `GrokStudio` for macOS)
- [ ] The code builds with no warnings (check with `swift build -Xswiftc -warnings-as-errors`)
- [ ] No API keys, tokens, or other secrets appear in code, test fixtures, logs, or screenshots

## Screenshots

<!-- Optional: for changes to the example apps, add before-and-after screenshots. -->
