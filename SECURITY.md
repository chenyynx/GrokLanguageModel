# Security Policy

## Supported versions

Security fixes are released for the latest minor version of the current major
version.

| Version | Supported |
| --- | --- |
| 1.x | Yes |
| Earlier than 1.0 | No |

## Reporting a vulnerability

Please don't report security vulnerabilities in public issues, discussions, or
pull requests.

Instead, report them privately through GitHub's security advisories:

**[Report a vulnerability](https://github.com/MarcoDotIO/GrokLanguageModel/security/advisories/new)**

Include as much of the following as you can:

- A description of the vulnerability and its impact
- The affected versions, platforms, and configuration
- Steps to reproduce it, or a proof of concept
- Any suggested fix or mitigation

Never include a real API key in a report. If a key is needed to reproduce the
issue, describe how it's used instead.

You'll receive an acknowledgment of your report, and updates as it's
investigated. Once a fix is ready, it's published in a new release along with
a GitHub security advisory that credits you, unless you'd prefer to stay
anonymous. Please keep the report confidential until the fix is released.

### Scope

In scope are vulnerabilities in this repository's code, including the package
and the example apps: for example, an API key leaking into logs, descriptions,
or requests to an unintended host, like an environment variable's key reaching
a server that isn't xAI, or mishandling of server responses.

Out of scope:

- Issues with the xAI API or your xAI account. Report those to xAI.
- Issues in Apple's Foundation Models framework. Report those to Apple.
- API keys that you exposed yourself. See [If a key leaks](#if-a-key-leaks).

## Handling API keys

An xAI API key authorizes requests that are billed to your account, so treat
it like a password.

- **Don't ship your key in an app.** Anyone can extract a key that's embedded
  in an app binary, no matter how it's obfuscated. For production apps, set
  `GrokConfiguration.baseURL` to your own server, which authenticates your
  users, adds the key, and forwards requests to the xAI API. When the base URL
  isn't an xAI host, the package doesn't require a key in the app.
- **Store user-provided keys in the Keychain.** If your users bring their own
  keys, like in the example apps, store them in the Keychain rather than in
  `UserDefaults`, files, or source code.
- **Only send `apiKey` to servers you trust.** The package sends a key that
  you set in `GrokConfiguration.apiKey` to whatever `baseURL` you set, in the
  `Authorization` header. Only combine a key with a custom `baseURL` for
  servers you control, and always use an `https` URL.
- **Use environment variables for development only.** When no key is
  configured, the package falls back to the `GROK_API_KEY` or `XAI_API_KEY`
  environment variable, but only for requests to an xAI host (`x.ai` or one of
  its subdomains) over `https`. It never reads them for a custom `baseURL`, so
  a development key can't leak to your own server or a third party.
  `GrokConfiguration.apiKeySource` tells you which key requests use without
  exposing it. To run this repository's live tests, keep your key in a `.env`
  file, which `.gitignore` excludes, and never commit it.
- **Use secrets in CI.** Store keys as encrypted secrets, and restrict them to
  trusted branches. This project keeps its key in the `grok-api` GitHub Actions
  environment, which only the `main` branch and version tags can use, so pull
  requests never see it.

The package itself doesn't log requests, and `GrokConfiguration`'s
`description`, `debugDescription`, and mirror redact the API key, the values
of additional headers, and any credentials in the base URL.

### If a key leaks

If you expose a key, for example by committing it or including it in an app,
revoke it right away in the [xAI Console](https://console.x.ai) and create a
new one. Removing the key from your repository's history isn't enough, because
it may already have been copied.
