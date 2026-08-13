import Foundation
import XCTest

final class SupabaseAuthTests: XCTestCase {
    override func tearDown() {
        AuthTestURLProtocol.handler = nil
        super.tearDown()
    }

    func testNonceIsRandomAndSHA256UsesExpectedDigest() throws {
        let first = try AppleNonce.random(length: 32)
        let second = try AppleNonce.random(length: 32)

        XCTAssertEqual(first.count, 32)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(
            AppleNonce.sha256("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testAppleExchangeSendsProviderIDTokenAndHashedNonceInputs() async throws {
        let configuration = try SupabaseAuthConfiguration(
            supabaseURLString: "https://project.supabase.co",
            publishableKey: "publishable-key"
        )
        let session = makeURLSession()
        let client = SupabaseAuthClient(configuration: configuration, session: session)
        let credential = AppleAuthorizationCredential(
            identityToken: "apple.identity.token",
            authorizationCode: "apple.authorization.code",
            userIdentifier: "apple-user",
            rawNonce: "raw-nonce"
        )
        let userID = UUID()

        AuthTestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/auth/v1/token")
            XCTAssertEqual(request.url?.query, "grant_type=id_token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "publishable-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

            let body = try? JSONSerialization.jsonObject(with: requestBodyData(request)) as? [String: String]
            XCTAssertEqual(body?["provider"], "apple")
            XCTAssertEqual(body?["id_token"], "apple.identity.token")
            XCTAssertEqual(body?["nonce"], "raw-nonce")
            XCTAssertNil(body?["authorization_code"])

            return .json(statusCode: 200, object: [
                "access_token": "access-token",
                "refresh_token": "refresh-token",
                "token_type": "bearer",
                "expires_in": 3600,
                "user": ["id": userID.uuidString]
            ])
        }

        let result = try await client.exchangeAppleCredential(credential)

        XCTAssertEqual(result.accessToken, "access-token")
        XCTAssertEqual(result.refreshToken, "refresh-token")
        XCTAssertEqual(result.userID, userID)
    }

    func testExpiredRestoredSessionRefreshesAndPersists() async throws {
        let oldSession = makeSession(accessToken: "old", expiresAt: Date(timeIntervalSinceNow: -60))
        let refreshed = makeSession(accessToken: "fresh", expiresAt: Date(timeIntervalSinceNow: 3600))
        let store = InMemorySessionStore(session: oldSession)
        let client = MockSupabaseAuthClient(refreshedSession: refreshed)
        let coordinator = SupabaseAuthSessionCoordinator(client: client, store: store)

        let restored = try await coordinator.restore()

        XCTAssertEqual(restored, refreshed)
        XCTAssertEqual(try store.load(), refreshed)
        let refreshCount = await client.refreshCount
        XCTAssertEqual(refreshCount, 1)
    }

    func testConcurrentRefreshRequestsShareOneRefreshTask() async throws {
        let expired = makeSession(accessToken: "expired", expiresAt: Date(timeIntervalSinceNow: -60))
        let refreshed = makeSession(accessToken: "fresh", expiresAt: Date(timeIntervalSinceNow: 3600))
        let client = MockSupabaseAuthClient(refreshedSession: refreshed, refreshDelay: 0.05)
        let coordinator = SupabaseAuthSessionCoordinator(
            client: client,
            store: InMemorySessionStore(session: expired)
        )

        async let first = coordinator.accessToken()
        async let second = coordinator.accessToken()

        let firstToken = try await first
        let secondToken = try await second
        let refreshCount = await client.refreshCount
        XCTAssertEqual(firstToken, "fresh")
        XCTAssertEqual(secondToken, "fresh")
        XCTAssertEqual(refreshCount, 1)
    }

    func testSignOutClearsLocalSessionAndCallsRemoteLogout() async throws {
        let session = makeSession(accessToken: "access", expiresAt: Date(timeIntervalSinceNow: 3600))
        let store = InMemorySessionStore(session: session)
        let client = MockSupabaseAuthClient(refreshedSession: session)
        let coordinator = SupabaseAuthSessionCoordinator(client: client, store: store)
        _ = try await coordinator.restore()

        try await coordinator.signOut()

        XCTAssertNil(try store.load())
        let signOutCount = await client.signOutCount
        XCTAssertEqual(signOutCount, 1)
    }

    @MainActor
    func testAuthServiceSignOutClearsSessionAndPublishesSignedOut() async throws {
        let session = makeSession(accessToken: "access", expiresAt: Date(timeIntervalSinceNow: 3600))
        let store = InMemorySessionStore(session: session)
        let client = MockSupabaseAuthClient(refreshedSession: session)
        let service = SupabaseAuthService(
            coordinator: SupabaseAuthSessionCoordinator(client: client, store: store)
        )

        await service.restoreSession()
        XCTAssertEqual(service.state, .signedIn(session))

        await service.signOut()

        XCTAssertEqual(service.state, .signedOut)
        XCTAssertNil(try store.load())
        let signOutCount = await client.signOutCount
        XCTAssertEqual(signOutCount, 1)
    }

    func testMissingSessionDoesNotProduceAnEmptyBearerToken() async throws {
        let coordinator = SupabaseAuthSessionCoordinator(
            client: MockSupabaseAuthClient(refreshedSession: makeSession()),
            store: InMemorySessionStore(session: nil)
        )

        do {
            _ = try await coordinator.accessToken()
            XCTFail("Expected missing session")
        } catch let error as SupabaseAuthError {
            XCTAssertEqual(error, .missingSession)
        }
    }

    func testAPIClientUsesCoordinatorTokenProvider() async throws {
        let session = makeSession(accessToken: "api-token", expiresAt: Date(timeIntervalSinceNow: 3600))
        let coordinator = SupabaseAuthSessionCoordinator(
            client: MockSupabaseAuthClient(refreshedSession: session),
            store: InMemorySessionStore(session: session)
        )
        let apiConfiguration = try APIConfiguration(baseURLString: "https://api.example.test")
        let apiClient = APIClient(
            configuration: apiConfiguration,
            session: makeURLSession(),
            tokenProvider: coordinator
        )

        AuthTestURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer api-token")
            return .json(statusCode: 200, object: ["status": "ok"])
        }

        let response = try await apiClient.get(RemoteHealthDTO.self, path: "/v1/bootstrap")
        XCTAssertEqual(response.status, "ok")
    }

    func testAPIClientSurfaces401WithoutRetryingAfterFreshToken() async throws {
        let session = makeSession(accessToken: "api-token", expiresAt: Date(timeIntervalSinceNow: 3600))
        let coordinator = SupabaseAuthSessionCoordinator(
            client: MockSupabaseAuthClient(refreshedSession: session),
            store: InMemorySessionStore(session: session)
        )
        let apiConfiguration = try APIConfiguration(baseURLString: "https://api.example.test")
        let apiClient = APIClient(
            configuration: apiConfiguration,
            session: makeURLSession(),
            tokenProvider: coordinator
        )
        var requestCount = 0

        AuthTestURLProtocol.handler = { request in
            requestCount += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer api-token")
            return .json(statusCode: 401, object: ["detail": "expired"])
        }

        do {
            _ = try await apiClient.get(RemoteHealthDTO.self, path: "/v1/bootstrap")
            XCTFail("Expected unauthorized response")
        } catch let error as AppError {
            XCTAssertEqual(error, .unauthorized)
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized("expired"))
        }
        XCTAssertEqual(requestCount, 2)
    }

    @MainActor
    func testAuthErrorMappingDoesNotExposeRawFailureDetails() {
        XCTAssertEqual(SupabaseAuthService.presentationError(for: .exchangeFailed("raw response")), .exchange)
        XCTAssertEqual(SupabaseAuthService.presentationError(for: .network("transport details")), .network)
        XCTAssertEqual(SupabaseAuthService.presentationError(for: .userCancelled), .credential)
    }

    @MainActor
    func testCancelledSignInReturnsToSignedOutState() async {
        let service = SupabaseAuthService(
            coordinator: SupabaseAuthSessionCoordinator(
                client: MockSupabaseAuthClient(
                    refreshedSession: makeSession(),
                    exchangeError: .userCancelled
                ),
                store: InMemorySessionStore(session: nil)
            )
        )

        await service.signIn(with: AppleAuthorizationCredential(
            identityToken: "token",
            userIdentifier: "apple-user",
            rawNonce: "nonce"
        ))

        XCTAssertEqual(service.state, .signedOut)
    }

    private func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthTestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeSession(
        accessToken: String = "access",
        expiresAt: Date = Date(timeIntervalSinceNow: 3600)
    ) -> SupabaseAuthSession {
        SupabaseAuthSession(
            accessToken: accessToken,
            refreshToken: "refresh",
            expiresAt: expiresAt,
            userID: UUID()
        )
    }
}

private final class InMemorySessionStore: SupabaseSessionStore, @unchecked Sendable {
    private var value: SupabaseAuthSession?

    init(session: SupabaseAuthSession?) {
        value = session
    }

    func load() throws -> SupabaseAuthSession? { value }
    func save(_ session: SupabaseAuthSession) throws { value = session }
    func clear() throws { value = nil }
}

private actor MockSupabaseAuthClient: SupabaseAuthClientProtocol {
    let refreshedSession: SupabaseAuthSession
    let refreshDelay: TimeInterval
    let exchangeError: SupabaseAuthError?
    private(set) var refreshCount = 0
    private(set) var signOutCount = 0

    init(
        refreshedSession: SupabaseAuthSession,
        refreshDelay: TimeInterval = 0,
        exchangeError: SupabaseAuthError? = nil
    ) {
        self.refreshedSession = refreshedSession
        self.refreshDelay = refreshDelay
        self.exchangeError = exchangeError
    }

    func exchangeAppleCredential(_ credential: AppleAuthorizationCredential) async throws -> SupabaseAuthSession {
        if let exchangeError { throw exchangeError }
        return refreshedSession
    }

    func refreshSession(refreshToken: String) async throws -> SupabaseAuthSession {
        refreshCount += 1
        if refreshDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(refreshDelay * 1_000_000_000))
        }
        return refreshedSession
    }

    func signOut(accessToken: String) async throws {
        signOutCount += 1
    }
}

private func requestBodyData(_ request: URLRequest) -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(buffer, count: count)
    }
    return data
}

private final class AuthTestURLProtocol: URLProtocol {
    struct Result {
        let statusCode: Int
        let data: Data
        let headers: [String: String]
        let error: Error?

        static func json(statusCode: Int, object: Any) -> Result {
            Result(
                statusCode: statusCode,
                data: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(),
                headers: ["Content-Type": "application/json"],
                error: nil
            )
        }
    }

    static var handler: ((URLRequest) -> Result)?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.example.test" || request.url?.host == "project.supabase.co"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let result = handler(request)
        if let error = result.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: result.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: result.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
