import Foundation

public enum APIConfigurationError: Error, Equatable, Sendable {
    case missingBaseURL
    case invalidBaseURL(String)
    case unsupportedScheme(String)
    case baseURLMustNotContainCredentials
}

public struct APIConfiguration: Equatable, Sendable {
    public static let baseURLInfoKey = "API_BASE_URL"

    public let baseURL: URL

    public init(baseURL: URL) throws {
        guard let scheme = baseURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw APIConfigurationError.unsupportedScheme(baseURL.scheme ?? "")
        }
        guard baseURL.user == nil && baseURL.password == nil else {
            throw APIConfigurationError.baseURLMustNotContainCredentials
        }
        guard baseURL.query == nil && baseURL.fragment == nil else {
            throw APIConfigurationError.invalidBaseURL("The base URL must not contain a query or fragment.")
        }

        var normalized = baseURL
        if !normalized.absoluteString.hasSuffix("/") {
            normalized.appendPathComponent("")
        }
        self.baseURL = normalized
    }

    public init(baseURLString: String?) throws {
        guard let baseURLString, !baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIConfigurationError.missingBaseURL
        }
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw APIConfigurationError.invalidBaseURL(baseURLString)
        }
        try self.init(baseURL: url)
    }

    /// Reads a non-secret API endpoint from the bundle, with an optional
    /// process-environment override for local/staging schemes.
    public static func current(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> APIConfiguration {
        let environmentValue = environment[baseURLInfoKey]
        let bundleValue = bundle.object(forInfoDictionaryKey: baseURLInfoKey) as? String
        var value = environmentValue ?? bundleValue

        if value == "$(API_BASE_URL)" {
            value = nil
        }

        #if DEBUG
        if value == nil || value == "$(API_BASE_URL)" {
            value = "http://127.0.0.1:8000"
        }
        #endif

        return try APIConfiguration(baseURLString: value)
    }

    func url(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard path.hasPrefix("/") else {
            throw APIConfigurationError.invalidBaseURL("API paths must start with '/'.")
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let combinedPath = [basePath, endpointPath].filter { !$0.isEmpty }.joined(separator: "/")
        components?.path = "/" + combinedPath
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw APIConfigurationError.invalidBaseURL(path)
        }
        return url
    }
}
