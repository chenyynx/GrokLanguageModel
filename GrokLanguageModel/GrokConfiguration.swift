//
//  GrokConfiguration.swift
//  GrokLanguageModel
//
//  Created by Marcus Arnett on 9/28/26.
//

import Foundation
import Synchronization

/// Settings that describe how Grok models connect to the xAI API.
///
/// Set an API key on ``default`` once, before you create sessions, to use it
/// with every Grok model:
///
/// ```swift
/// GrokConfiguration.default.apiKey = "<your xAI API key>"
/// ```
///
/// If a configuration has no API key, requests to the xAI API fall back to the
/// `GROK_API_KEY` or `XAI_API_KEY` environment variable, which is convenient
/// during development and testing. Requests to other hosts, like your own
/// server, and requests that don't use HTTPS never read those environment
/// variables. Check ``apiKeySource`` to find out which key requests use.
///
/// > Important: An API key that ships inside an app can be extracted from it.
/// > In production, consider pointing ``baseURL`` at your own server that adds
/// > the key and forwards requests to the xAI API.
public struct GrokConfiguration: Sendable {
    /// The base URL of the xAI API.
    public static let xAIBaseURL = URL(string: "https://api.x.ai/v1")!

    /// The API key to authenticate requests with.
    ///
    /// Requests send this key to ``baseURL`` regardless of its host, so only
    /// set it for base URLs that you trust. When this is `nil` or empty,
    /// requests to an xAI host, like `api.x.ai`, over HTTPS use the
    /// `GROK_API_KEY` environment variable, then `XAI_API_KEY`, and requests
    /// to other hosts don't send an API key.
    public var apiKey: String?

    /// The base URL that requests are sent to.
    ///
    /// Requests go to the `responses` endpoint relative to this URL.
    public var baseURL: URL

    /// Additional HTTP headers to send with every request.
    public var additionalHeaders: [String: String]

    /// How long a request waits for new data before it times out, in seconds.
    public var timeoutInterval: TimeInterval

    /// The URL session that sends requests.
    public var urlSession: URLSession

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - apiKey: The API key to authenticate requests with.
    ///   - baseURL: The base URL that requests are sent to.
    ///   - additionalHeaders: Additional HTTP headers to send with every request.
    ///   - timeoutInterval: How long a request waits for new data before it times out, in seconds.
    ///   - urlSession: The URL session that sends requests.
    public init(
        apiKey: String? = nil,
        baseURL: URL = xAIBaseURL,
        additionalHeaders: [String: String] = [:],
        timeoutInterval: TimeInterval = 600,
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.additionalHeaders = additionalHeaders
        self.timeoutInterval = timeoutInterval
        self.urlSession = urlSession
    }
}

extension GrokConfiguration {
    /// The configuration that Grok models use when they don't have their own.
    ///
    /// Reading and setting this property is thread-safe. A change to one of
    /// its properties, like `GrokConfiguration.default.apiKey = key`, reads
    /// the configuration and then sets the whole configuration, though, so
    /// when several tasks might change it at the same time, use
    /// ``updateDefault(_:)`` instead, which makes each change atomically.
    public static var `default`: GrokConfiguration {
        get { defaultConfiguration.withLock { $0 } }
        set { defaultConfiguration.withLock { $0 = newValue } }
    }

    /// Changes the default configuration atomically.
    ///
    /// Unlike setting a property of ``default``, this method holds a lock
    /// while `body` runs, so changes that several tasks make at the same time
    /// don't overwrite each other:
    ///
    /// ```swift
    /// GrokConfiguration.updateDefault { configuration in
    ///     configuration.additionalHeaders["X-Client-Version"] = "2.1"
    /// }
    /// ```
    ///
    /// - Parameter body: A closure that changes the configuration in place.
    ///   Keep it short, because other accesses to ``default`` wait for it.
    public static func updateDefault<Failure: Error>(
        _ body: (inout GrokConfiguration) throws(Failure) -> Void
    ) throws(Failure) {
        try defaultConfiguration.withLock { (configuration: inout sending GrokConfiguration) throws(Failure) in
            try body(&configuration)
        }
    }
}

private let defaultConfiguration = Mutex(GrokConfiguration())

extension GrokConfiguration: Hashable {
    public static func == (lhs: GrokConfiguration, rhs: GrokConfiguration) -> Bool {
        lhs.apiKey == rhs.apiKey
            && lhs.baseURL == rhs.baseURL
            && lhs.additionalHeaders == rhs.additionalHeaders
            && lhs.timeoutInterval == rhs.timeoutInterval
            && lhs.urlSession === rhs.urlSession
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(apiKey)
        hasher.combine(baseURL)
        hasher.combine(additionalHeaders)
        hasher.combine(timeoutInterval)
        hasher.combine(ObjectIdentifier(urlSession))
    }
}

// Keep the API key, header values, and any credentials in the base URL out of
// logs and debugger output.
extension GrokConfiguration: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "GrokConfiguration(baseURL: \(redactedBaseURL), apiKey: \(apiKey == nil ? "nil" : "<redacted>"))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: [
            "apiKey": apiKey == nil ? "nil" : "<redacted>",
            "baseURL": redactedBaseURL,
            "additionalHeaders": additionalHeaders.keys.sorted(),
            "timeoutInterval": timeoutInterval,
        ], displayStyle: .struct)
    }

    /// The base URL, with its user name, password, query, and fragment, which
    /// can hold credentials for a proxy server, redacted.
    private var redactedBaseURL: String {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return "<redacted>"
        }
        let hasUserInfo = components.user != nil || components.password != nil
        let hasQuery = components.query != nil
        let hasFragment = components.fragment != nil
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        guard var redacted = components.string else { return "<redacted>" }
        if hasUserInfo, let authority = redacted.range(of: "//") {
            redacted.insert(contentsOf: "<redacted>@", at: authority.upperBound)
        }
        if hasQuery {
            redacted += "?<redacted>"
        }
        if hasFragment {
            redacted += "#<redacted>"
        }
        return redacted
    }
}

// MARK: - API key source

extension GrokConfiguration {
    /// Where the API key that requests send comes from.
    ///
    /// The package only adds cases to this enumeration in a new major
    /// version, so a `switch` over it that handles every case keeps compiling
    /// throughout a major version.
    public enum APIKeySource: Hashable, Sendable {
        /// The configuration's ``GrokConfiguration/apiKey``.
        case configuration

        /// The environment variable named `variable`, like `GROK_API_KEY`.
        case environment(variable: String)
    }

    /// Where the API key that requests send comes from, or `nil` if they don't
    /// send one.
    ///
    /// Requests use ``apiKey`` when it isn't empty. Otherwise, requests to an
    /// xAI host over HTTPS use the `GROK_API_KEY` environment variable, then
    /// `XAI_API_KEY`. Use this property to show which key an app uses without
    /// reading the key itself.
    public var apiKeySource: APIKeySource? {
        resolvedAPIKey(environment: ProcessInfo.processInfo.environment)?.source
    }
}

// MARK: - Requests

extension GrokConfiguration {
    /// The environment variables that requests to an xAI host read an API key
    /// from, in order.
    static let apiKeyEnvironmentVariables = ["GROK_API_KEY", "XAI_API_KEY"]

    /// The API key that requests send, and where it comes from.
    ///
    /// This is ``apiKey`` when it isn't empty. Otherwise, if requests go to an
    /// xAI host over HTTPS, it's the first nonempty environment variable in
    /// ``apiKeyEnvironmentVariables``. The environment is never read for other
    /// hosts or for plain HTTP, so a custom ``baseURL`` can't receive a key
    /// from it, and a key from it is never sent in cleartext.
    func resolvedAPIKey(environment: [String: String]) -> (key: String, source: APIKeySource)? {
        if let apiKey, !apiKey.isEmpty {
            return (apiKey, .configuration)
        }
        guard allowsEnvironmentAPIKey else { return nil }
        for variable in Self.apiKeyEnvironmentVariables {
            if let key = environment[variable], !key.isEmpty {
                return (key, .environment(variable: variable))
            }
        }
        return nil
    }

    /// Whether requests go to an xAI host, which requires an API key.
    var requiresAPIKey: Bool {
        guard let host = baseURL.host()?.lowercased() else { return false }
        return host == "x.ai" || host.hasSuffix(".x.ai")
    }

    /// Whether requests can use an API key from the environment, which is
    /// only the case for requests to an xAI host over HTTPS.
    var allowsEnvironmentAPIKey: Bool {
        baseURL.scheme?.lowercased() == "https" && requiresAPIKey
    }

    func makeURLRequest(
        body: some Encodable,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "responses"), timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let apiKey = resolvedAPIKey(environment: environment)?.key {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        } else if requiresAPIKey {
            throw GrokError.missingAPIKey
        }
        for (field, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        // Write the body with an ordered writer, instead of with JSONEncoder,
        // so that the properties of JSON schemas for guided generation and
        // tool arguments keep their declaration order, which is the order the
        // model generates them in.
        request.httpBody = try JSONValue(encoding: body).jsonData()
        return request
    }
}
