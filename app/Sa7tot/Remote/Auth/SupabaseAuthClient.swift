import Foundation

public protocol SupabaseAuthClientProtocol: Sendable {
    func exchangeAppleCredential(_ credential: AppleAuthorizationCredential) async throws -> SupabaseAuthSession
    func refreshSession(refreshToken: String) async throws -> SupabaseAuthSession
    func signOut(accessToken: String) async throws
}

public final class SupabaseAuthClient: SupabaseAuthClientProtocol, @unchecked Sendable {
    private let configuration: SupabaseAuthConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(configuration: SupabaseAuthConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func exchangeAppleCredential(_ credential: AppleAuthorizationCredential) async throws -> SupabaseAuthSession {
        struct AppleIDTokenRequest: Encodable {
            let provider = "apple"
            let idToken: String
            let nonce: String

            enum CodingKeys: String, CodingKey {
                case provider
                case idToken = "id_token"
                case nonce
            }
        }

        let request = try makeRequest(
            method: "POST",
            path: "/auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "id_token")],
            body: AppleIDTokenRequest(
                idToken: credential.identityToken,
                nonce: credential.rawNonce
            )
        )
        let response: AuthResponseDTO = try await send(request, failure: { .exchangeFailed($0) })
        return try response.session(fallbackRefreshToken: nil)
    }

    public func refreshSession(refreshToken: String) async throws -> SupabaseAuthSession {
        struct RefreshRequest: Encodable {
            let refreshToken: String

            enum CodingKeys: String, CodingKey {
                case refreshToken = "refresh_token"
            }
        }

        let request = try makeRequest(
            method: "POST",
            path: "/auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: RefreshRequest(refreshToken: refreshToken)
        )
        let response: AuthResponseDTO = try await send(request, failure: { .refreshFailed($0) })
        return try response.session(fallbackRefreshToken: refreshToken)
    }

    public func signOut(accessToken: String) async throws {
        let request = try makeRequest(method: "POST", path: "/auth/v1/logout", accessToken: accessToken)
        do {
            _ = try await sendEmpty(request)
        } catch let error as SupabaseAuthError {
            throw error
        }
    }

    private func makeRequest<Body: Encodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body? = nil,
        accessToken: String? = nil
    ) throws -> URLRequest {
        let url: URL
        do {
            url = try configuration.url(path: path, queryItems: queryItems)
        } catch {
            throw SupabaseAuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func makeRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        accessToken: String? = nil
    ) throws -> URLRequest {
        try makeRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            body: Optional<EmptyBody>.none,
            accessToken: accessToken
        )
    }

    private func send<Response: Decodable>(
        _ request: URLRequest,
        failure: @escaping (String?) -> SupabaseAuthError
    ) async throws -> Response {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SupabaseAuthError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw failure(Self.message(from: data))
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw SupabaseAuthError.decoding("The Supabase auth response was invalid.")
            }
        } catch is CancellationError {
            throw SupabaseAuthError.userCancelled
        } catch let error as URLError where error.code == .cancelled {
            throw SupabaseAuthError.userCancelled
        } catch let error as SupabaseAuthError {
            throw error
        } catch let error as URLError {
            throw error
        } catch {
            throw SupabaseAuthError.network(error.localizedDescription)
        }
    }

    private func sendEmpty(_ request: URLRequest) async throws {
        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SupabaseAuthError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw SupabaseAuthError.signOutFailed(nil)
            }
        } catch is CancellationError {
            throw SupabaseAuthError.userCancelled
        } catch let error as SupabaseAuthError {
            throw error
        } catch {
            throw SupabaseAuthError.network(error.localizedDescription)
        }
    }

    private static func message(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["msg"] as? String
            ?? object["message"] as? String
            ?? object["error_description"] as? String
            ?? object["error"] as? String
    }
}

private struct EmptyBody: Encodable {}

private struct AuthResponseDTO: Decodable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: Int?
    let expiresAt: Int?
    let user: UserDTO

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }

    func session(fallbackRefreshToken: String?) throws -> SupabaseAuthSession {
        guard let userID = UUID(uuidString: user.id), !accessToken.isEmpty else {
            throw SupabaseAuthError.invalidResponse
        }
        guard let refreshToken = refreshToken ?? fallbackRefreshToken, !refreshToken.isEmpty else {
            throw SupabaseAuthError.invalidResponse
        }

        let expiration = expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            ?? Date().addingTimeInterval(TimeInterval(expiresIn ?? 0))
        return SupabaseAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType ?? "bearer",
            expiresAt: expiration,
            userID: userID
        )
    }
}

private struct UserDTO: Decodable {
    let id: String
}
