import Foundation
import XCTest

final class RemoteAPIClientTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.handler = nil
        super.tearDown()
    }

    func testAuthenticatedRequestIncludesBearerTokenAndQueryItems() async throws {
        let client = try makeClient(token: "test-jwt")
        let expected = RemoteHealthDTO(status: "ok")

        TestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/bootstrap")
            XCTAssertEqual(request.url?.query, "limit=10&cursor=next-page")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-jwt")
            return .json(statusCode: 200, object: ["status": "ok"])
        }

        let request = APIRequest<RemoteHealthDTO>(
            method: .get,
            path: "/v1/bootstrap",
            queryItems: [
                URLQueryItem(name: "limit", value: "10"),
                URLQueryItem(name: "cursor", value: "next-page")
            ]
        )
        let response = try await client.send(request)
        XCTAssertEqual(response, expected)
    }

    func testMovimentiRepositoryBuildsSubscriptionFilterRequest() async throws {
        let client = try makeClient(token: "subscription-token")
        let accountID = UUID()

        TestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/accounts/\(accountID.uuidString)/movements")
            XCTAssertEqual(request.url?.query, "limit=50&filter=subscription")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer subscription-token")
            return .json(statusCode: 200, object: [
                "account": [
                    "id": accountID.uuidString,
                    "name": "Principale",
                    "currency_code": "EUR",
                    "currency_exponent": 2,
                    "balance_minor": 0
                ],
                "summary": ["income_minor": 0, "expenses_minor": 0],
                "days": [],
                "next_cursor": NSNull()
            ])
        }

        let page = try await RemoteMovimentiRepository(client: client).page(
            accountID: accountID,
            limit: 50,
            filter: "subscription"
        )
        XCTAssertEqual(page.account.id, accountID)
        XCTAssertTrue(page.days.isEmpty)
    }

    func testMovimentiRepositoryPreservesWeekAndMonthPeriodQueryShape() async throws {
        let client = try makeClient(token: "period-token")
        let accountID = UUID()
        let weekStart = try RemoteDateOnly(isoString: "2026-08-10")

        TestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/accounts/\(accountID.uuidString)/movements")
            XCTAssertEqual(request.url?.query, "limit=50&filter=week&week_start=2026-08-10&month=2026-08-01")
            return .json(statusCode: 200, object: [
                "account": [
                    "id": accountID.uuidString,
                    "name": "Principale",
                    "currency_code": "EUR",
                    "currency_exponent": 2,
                    "balance_minor": 0
                ],
                "summary": ["income_minor": 0, "expenses_minor": 0],
                "days": [],
                "next_cursor": NSNull()
            ])
        }

        let page = try await RemoteMovimentiRepository(client: client).page(
            accountID: accountID,
            limit: 50,
            filter: "week",
            weekStart: weekStart,
            month: "2026-08-01"
        )
        XCTAssertEqual(page.account.id, accountID)
    }

    func testPublicHealthRequestDoesNotIncludeAuthorization() async throws {
        let client = try makeClient(token: nil)

        TestURLProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.url?.path, "/health")
            return .json(statusCode: 200, object: ["status": "ok"])
        }

        let request = APIRequest<RemoteHealthDTO>(method: .get, path: "/health", authentication: .public)
        let response = try await client.send(request)
        XCTAssertEqual(response.status, "ok")
    }

    func testJSONBodyAndHTTPMethodAreForwarded() async throws {
        let client = try makeClient(token: "token")
        let payload = TestPayload(name: "Caffè", amountMinor: 1250)

        TestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try? JSONDecoder().decode(TestPayload.self, from: requestBodyData(request))
            XCTAssertEqual(body, payload)
            return .json(statusCode: 200, object: ["status": "accepted"])
        }

        let request = try APIRequest<RemoteHealthDTO>(
            method: .post,
            path: "/v1/test",
            body: payload
        )
        let response = try await client.send(request)
        XCTAssertEqual(response.status, "accepted")
    }

    func testProfileUpdateUsesAuthenticatedPatchAndDecodesProfile() async throws {
        let client = try makeClient(token: "profile-token")
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let payload = RemoteProfileUpdatePayload(monthStartDay: 15, weekStartDay: 3)

        TestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/v1/profile")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer profile-token")
            let body = try? JSONSerialization.jsonObject(with: requestBodyData(request)) as? [String: Any]
            XCTAssertEqual(body?["month_start_day"] as? Int, 15)
            XCTAssertEqual(body?["week_start_day"] as? Int, 3)
            return .json(statusCode: 200, object: [
                "user_id": userID.uuidString,
                "locale": "it-IT",
                "timezone": "Europe/Rome",
                "default_currency_code": "EUR",
                "month_start_day": 15,
                "week_start_day": 3
            ])
        }

        let profile = try await RemoteBootstrapRepository(client: client).updateProfile(payload)
        XCTAssertEqual(profile.userID, userID)
        XCTAssertEqual(profile.defaultCurrencyCode, "EUR")
        XCTAssertEqual(profile.monthStartDay, 15)
        XCTAssertEqual(profile.weekStartDay, 3)
    }

    func testMissingProviderDoesNotSilentlyBypassAuthentication() async throws {
        let client = try makeClient(token: nil)
        let request = APIRequest<RemoteHealthDTO>(method: .get, path: "/v1/bootstrap")

        do {
            _ = try await client.send(request)
            XCTFail("Expected authentication boundary error")
        } catch let error as AppError {
            XCTAssertEqual(error, .configuration)
        }
    }

    func testAppErrorTransportMapping() async throws {
        let cases: [(URLError.Code, AppError)] = [
            (.notConnectedToInternet, .networkUnavailable),
            (.networkConnectionLost, .networkUnavailable),
            (.cannotConnectToHost, .connectionFailed),
            (.cannotFindHost, .connectionFailed),
            (.timedOut, .timeout),
            (.cancelled, .cancelled)
        ]

        for (code, expected) in cases {
            let client = try makeClient(token: nil)
            TestURLProtocol.handler = { _ in .failure(URLError(code)) }
            let request = APIRequest<RemoteHealthDTO>(method: .get, path: "/health", authentication: .public)

            do {
                _ = try await client.send(request)
                XCTFail("Expected transport error for \(code)")
            } catch let error as AppError {
                XCTAssertEqual(error, expected)
            } catch is CancellationError {
                XCTAssertEqual(expected, .cancelled)
            }
        }
    }

    func testAppErrorHTTPStatusMapping() async throws {
        let cases: [(Int, [String: String], Any, AppError)] = [
            (401, [:], ["detail": "unauthorized"], .unauthorized),
            (403, [:], ["detail": "forbidden"], .forbidden),
            (404, [:], ["detail": "not found"], .notFound),
            (409, [:], ["detail": "conflict occurred"], .conflict(message: "conflict occurred")),
            (422, [:], ["detail": "invalid input"], .validation(message: "invalid input")),
            (429, [:], ["detail": "rate limited"], .rateLimited(retryAfter: nil)),
            (429, ["Retry-After": "45"], ["detail": "rate limited"], .rateLimited(retryAfter: 45)),
            (500, [:], ["detail": "internal server error"], .serverUnavailable(statusCode: 500)),
            (503, [:], ["detail": "service unavailable"], .serverUnavailable(statusCode: 503))
        ]

        for (statusCode, headers, json, expected) in cases {
            let client = try makeClient(token: nil)
            TestURLProtocol.handler = { request in
                TestURLProtocol.Result(
                    statusCode: statusCode,
                    data: (try? JSONSerialization.data(withJSONObject: json)) ?? Data(),
                    headers: headers.merging(["Content-Type": "application/json"], uniquingKeysWith: { $1 }),
                    error: nil
                )
            }

            let request = APIRequest<RemoteHealthDTO>(method: .get, path: "/health", authentication: .public)
            do {
                _ = try await client.send(request)
                XCTFail("Expected HTTP \(statusCode) to fail")
            } catch let error as AppError {
                XCTAssertEqual(error, expected)
            }
        }
    }

    func testMalformedSuccessBodyReportsDecodingError() async throws {
        let client = try makeClient(token: nil)
        TestURLProtocol.handler = { _ in .raw(statusCode: 200, data: Data("not-json".utf8)) }

        do {
            _ = try await client.send(APIRequest<RemoteHealthDTO>(method: .get, path: "/health", authentication: .public))
            XCTFail("Expected decoding failure")
        } catch let error as AppError {
            guard case .decoding = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func test401TriggersAuthRefreshAndRetriesRequestOnce() async throws {
        let provider = TestRefreshedTokenProvider(currentToken: "expired-jwt", refreshedToken: "fresh-jwt")
        let client = try makeClientWithProvider(provider)

        var requestCount = 0
        TestURLProtocol.handler = { request in
            requestCount += 1
            if requestCount == 1 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer expired-jwt")
                return .json(statusCode: 401, object: ["detail": "token expired"])
            } else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-jwt")
                return .json(statusCode: 200, object: ["status": "ok"])
            }
        }

        let request = APIRequest<RemoteHealthDTO>(method: .get, path: "/v1/bootstrap", authentication: .required)
        let response = try await client.send(request)
        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(provider.refreshCallCount, 1)
    }

    func test401StillUnauthorizedNoInfiniteLoop() async throws {
        let provider = TestRefreshedTokenProvider(currentToken: "expired-jwt", refreshedToken: "still-invalid-jwt")
        let client = try makeClientWithProvider(provider)

        var requestCount = 0
        TestURLProtocol.handler = { request in
            requestCount += 1
            return .json(statusCode: 401, object: ["detail": "unauthorized"])
        }

        let request = APIRequest<RemoteHealthDTO>(method: .get, path: "/v1/bootstrap", authentication: .required)
        do {
            _ = try await client.send(request)
            XCTFail("Expected unauthorized error")
        } catch let error as AppError {
            XCTAssertEqual(error, .unauthorized)
        }
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(provider.refreshCallCount, 1)
    }

    func testRefreshFailureMapsToUnauthorizedForAuthInvalidation() async throws {
        let provider = TestRefreshedTokenProvider(
            currentToken: "expired-jwt",
            refreshError: SupabaseAuthError.refreshFailed("revoked")
        )
        let client = try makeClientWithProvider(provider)

        TestURLProtocol.handler = { _ in .json(statusCode: 401, object: ["detail": "expired"]) }

        let request = APIRequest<RemoteHealthDTO>(method: .get, path: "/v1/bootstrap", authentication: .required)
        do {
            _ = try await client.send(request)
            XCTFail("Expected unauthorized error")
        } catch let error as AppError {
            XCTAssertEqual(error, .unauthorized)
        }
        XCTAssertEqual(provider.refreshCallCount, 1)
    }

    func testRefreshFailurePreservesTransportWhenNetworkFails() async throws {
        let provider = TestRefreshedTokenProvider(
            currentToken: "expired-jwt",
            refreshError: URLError(.notConnectedToInternet)
        )
        let client = try makeClientWithProvider(provider)

        TestURLProtocol.handler = { _ in .json(statusCode: 401, object: ["detail": "expired"]) }

        let request = APIRequest<RemoteHealthDTO>(method: .get, path: "/v1/bootstrap", authentication: .required)
        do {
            _ = try await client.send(request)
            XCTFail("Expected network unavailable error")
        } catch let error as AppError {
            XCTAssertEqual(error, .networkUnavailable)
        }
        XCTAssertEqual(provider.refreshCallCount, 1)
    }

    func testCancellationIsPropagated() async throws {
        let client = try makeClient(token: nil)
        let request = APIRequest<RemoteHealthDTO>(method: .get, path: "/health", authentication: .public)
        let task = Task { try await client.send(request) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    private func makeClient(token: String?) throws -> APIClient {
        let provider = token.map(TestTokenProvider.init(token:))
        return try makeClientWithProvider(provider)
    }

    private func makeClientWithProvider(_ provider: AuthTokenProvider?) throws -> APIClient {
        let configuration = try APIConfiguration(baseURLString: "https://api.example.test")
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [TestURLProtocol.self]
        return APIClient(
            configuration: configuration,
            session: URLSession(configuration: sessionConfiguration),
            tokenProvider: provider
        )
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

private struct TestPayload: Codable, Equatable {
    let name: String
    let amountMinor: Int64
}

private struct TestTokenProvider: AuthTokenProvider {
    let token: String

    func accessToken() async throws -> String { token }
}

private final class TestRefreshedTokenProvider: AuthTokenProvider, @unchecked Sendable {
    var currentToken: String
    var refreshedToken: String?
    var refreshCallCount = 0
    var refreshError: Error?

    init(currentToken: String, refreshedToken: String? = nil, refreshError: Error? = nil) {
        self.currentToken = currentToken
        self.refreshedToken = refreshedToken
        self.refreshError = refreshError
    }

    func accessToken() async throws -> String { token }
    var token: String { currentToken }

    func refreshSession() async throws -> String {
        refreshCallCount += 1
        if let refreshError {
            throw refreshError
        }
        if let refreshedToken {
            currentToken = refreshedToken
            return refreshedToken
        }
        return currentToken
    }
}

private final class TestURLProtocol: URLProtocol {
    struct Result {
        let statusCode: Int
        let data: Data
        let headers: [String: String]
        let error: Error?

        static func json(statusCode: Int, object: Any) -> Result {
            let data: Data
            if JSONSerialization.isValidJSONObject(object), let jsonData = try? JSONSerialization.data(withJSONObject: object) {
                data = jsonData
            } else if let string = object as? String {
                data = Data(string.utf8)
            } else if let rawData = object as? Data {
                data = rawData
            } else {
                data = Data()
            }
            return Result(
                statusCode: statusCode,
                data: data,
                headers: ["Content-Type": "application/json"],
                error: nil
            )
        }

        static func raw(statusCode: Int, data: Data) -> Result {
            Result(statusCode: statusCode, data: data, headers: [:], error: nil)
        }

        static func failure(_ error: Error) -> Result {
            Result(statusCode: 0, data: Data(), headers: [:], error: error)
        }
    }

    static var handler: ((URLRequest) -> Result)?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.example.test"
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
