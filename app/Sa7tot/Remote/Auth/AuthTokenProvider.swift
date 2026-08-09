import Foundation

/// Supplies the access token for authenticated API requests.
///
/// The remote layer deliberately knows nothing about Apple Sign In or any
/// other authentication SDK. The eventual auth implementation can provide a
/// JWT here without changing APIClient or the repositories.
public protocol AuthTokenProvider: Sendable {
    func accessToken() async throws -> String
}
