import Foundation

public enum SupabaseAuthConfigurationError: Error, Equatable, Sendable {
    case missingSupabaseURL
    case invalidSupabaseURL
    case unsupportedSupabaseURLScheme
    case missingPublishableKey
}

public struct SupabaseAuthConfiguration: Equatable, Sendable {
    public static let urlInfoKey = "SUPABASE_URL"
    public static let publishableKeyInfoKey = "SUPABASE_PUBLISHABLE_KEY"

    public let supabaseURL: URL
    public let publishableKey: String

    public init(supabaseURL: URL, publishableKey: String) throws {
        guard let scheme = supabaseURL.scheme?.lowercased(), scheme == "https" else {
            throw SupabaseAuthConfigurationError.unsupportedSupabaseURLScheme
        }
        guard supabaseURL.user == nil && supabaseURL.password == nil,
              supabaseURL.query == nil,
              supabaseURL.fragment == nil else {
            throw SupabaseAuthConfigurationError.invalidSupabaseURL
        }
        guard !publishableKey.isEmpty, !publishableKey.contains("$(") else {
            throw SupabaseAuthConfigurationError.missingPublishableKey
        }

        self.supabaseURL = supabaseURL
        self.publishableKey = publishableKey
    }

    public init(supabaseURLString: String?, publishableKey: String?) throws {
        guard let supabaseURLString,
              !supabaseURLString.isEmpty,
              !supabaseURLString.contains("$(") else {
            throw SupabaseAuthConfigurationError.missingSupabaseURL
        }
        guard let url = URL(string: supabaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SupabaseAuthConfigurationError.invalidSupabaseURL
        }
        guard let publishableKey,
              !publishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !publishableKey.contains("$(") else {
            throw SupabaseAuthConfigurationError.missingPublishableKey
        }
        try self.init(supabaseURL: url, publishableKey: publishableKey)
    }

    public static func current(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> SupabaseAuthConfiguration {
        let url = environment[urlInfoKey] ?? bundle.object(forInfoDictionaryKey: urlInfoKey) as? String
        let key = environment[publishableKeyInfoKey]
            ?? bundle.object(forInfoDictionaryKey: publishableKeyInfoKey) as? String
        return try SupabaseAuthConfiguration(supabaseURLString: url, publishableKey: key)
    }

    func url(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard path.hasPrefix("/") else {
            throw SupabaseAuthConfigurationError.invalidSupabaseURL
        }

        var components = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components?.path = "/" + [basePath, endpointPath].filter { !$0.isEmpty }.joined(separator: "/")
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw SupabaseAuthConfigurationError.invalidSupabaseURL
        }
        return url
    }
}
