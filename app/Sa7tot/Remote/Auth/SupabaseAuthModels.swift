import Foundation

public struct SupabaseAuthSession: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let tokenType: String
    public let expiresAt: Date
    public let userID: UUID

    public init(
        accessToken: String,
        refreshToken: String,
        tokenType: String = "bearer",
        expiresAt: Date,
        userID: UUID
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.userID = userID
    }

    public func isValid(at date: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        !accessToken.isEmpty && expiresAt.timeIntervalSince(date) > leeway
    }
}

public struct AppleAuthorizationCredential: Equatable, Sendable {
    public let identityToken: String
    public let authorizationCode: String?
    public let userIdentifier: String
    public let rawNonce: String

    public init(
        identityToken: String,
        authorizationCode: String? = nil,
        userIdentifier: String,
        rawNonce: String
    ) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.userIdentifier = userIdentifier
        self.rawNonce = rawNonce
    }
}

public enum SupabaseAuthError: Error, Equatable, Sendable {
    case configuration(SupabaseAuthConfigurationError)
    case userCancelled
    case missingIdentityToken
    case invalidAppleCredential
    case exchangeFailed(String?)
    case refreshFailed(String?)
    case signOutFailed(String?)
    case missingSession
    case keychainFailure(OSStatus)
    case network(String)
    case decoding(String)
    case invalidResponse
}

public enum SupabaseAuthPresentationError: Equatable, Sendable {
    case configuration
    case network
    case credential
    case exchange
    case refresh
    case unknown

    public var message: String {
        switch self {
        case .configuration:
            return AppLocalization.string("auth.configuration")
        case .network:
            return AppLocalization.string("auth.network")
        case .credential, .exchange:
            return AppLocalization.string("auth.credential")
        case .refresh:
            return AppLocalization.string("auth.refresh")
        case .unknown:
            return AppLocalization.string("error.generic")
        }
    }
}

public enum SupabaseAuthState: Equatable, Sendable {
    case restoring
    case signedOut
    case signedIn(SupabaseAuthSession)
    case error(SupabaseAuthPresentationError)
}
