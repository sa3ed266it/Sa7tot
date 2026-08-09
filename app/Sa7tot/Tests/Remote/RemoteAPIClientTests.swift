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

    func testPutBudgetMutationUsesAuthenticatedRequestAndMinorUnits() async throws {
        let client = try makeClient(token: "budget-token")
        let payload = RemoteBudgetMutationPayload(
            amountMinor: 100000,
            currencyCode: "EUR",
            currencyExponent: 2,
            periodType: .month
        )
        TestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/v1/budget/main")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer budget-token")
            let object = try? JSONSerialization.jsonObject(with: requestBodyData(request)) as? [String: Any]
            XCTAssertEqual(object?["amount_minor"] as? Int, 100000)
            return .json(statusCode: 200, object: ["main": NSNull(), "categories": []])
        }

        let response = try await client.put(
            RemoteBudgetSummaryDTO.self,
            path: "/v1/budget/main",
            body: payload
        )
        XCTAssertNil(response.main)
        XCTAssertTrue(response.categories.isEmpty)
    }

    func testRecurrenceRepositoryUsesAuthenticatedRoutes() async throws {
        let client = try makeClient(token: "recurrence-token")
        let ruleID = UUID(uuidString: "00000000-0000-0000-0000-000000000050")!
        var paths: [String] = []
        TestURLProtocol.handler = { request in
            paths.append("\(request.httpMethod ?? "") \(request.url?.path ?? "")")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer recurrence-token")
            let rule: [String: Any] = [
                "id": ruleID.uuidString,
                "user_id": "00000000-0000-0000-0000-000000000001",
                "account_id": "00000000-0000-0000-0000-000000000010",
                "category_id": NSNull(),
                "kind": "expense",
                "amount_minor": 1299,
                "currency_code": "EUR",
                "currency_exponent": 2,
                "title": "Affitto",
                "note": NSNull(),
                "merchant": NSNull(),
                "cadence": "monthly",
                "cadence_interval": 1,
                "anchor_date": "2026-08-01",
                "next_occurrence_date": "2026-09-01",
                "status": "active",
                "created_at": "2026-08-01T10:00:00Z",
                "updated_at": "2026-08-01T10:00:00Z"
            ]
            return .json(statusCode: 200, object: rule)
        }

        let repository = RemoteRecurrencesRepository(client: client)
        _ = try await repository.resume(ruleID: ruleID)
        XCTAssertEqual(paths, ["POST /v1/recurrences/\(ruleID.uuidString)/resume"])
    }

    func testUpcomingRepositorySendsAccountAndWindowQuery() async throws {
        let client = try makeClient(token: "upcoming-token")
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        TestURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/accounts/\(accountID.uuidString)/upcoming")
            XCTAssertEqual(request.url?.query, "limit=50&days=14")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer upcoming-token")
            return .json(statusCode: 200, object: [
                "account": ["id": accountID.uuidString, "name": "Conto principale", "currency_code": "EUR"],
                "items": []
            ])
        }

        let repository = RemoteUpcomingRepository(client: client)
        let response = try await repository.list(accountID: accountID, limit: 50, days: 14)
        XCTAssertTrue(response.items.isEmpty)
    }

    func testMissingProviderDoesNotSilentlyBypassAuthentication() async throws {
        let client = try makeClient(token: nil)
        let request = APIRequest<RemoteHealthDTO>(method: .get, path: "/v1/bootstrap")

        do {
            _ = try await client.send(request)
            XCTFail("Expected authentication boundary error")
        } catch let error as APIError {
            XCTAssertEqual(error, .missingTokenProvider)
        }
    }

    func testHTTPStatusErrorsDecodeIntoUsefulAPIErrorCases() async throws {
        let cases: [(Int, APIError)] = [
            (401, .unauthorized("nope")),
            (403, .forbidden("blocked")),
            (404, .notFound("missing")),
            (422, .validation("bad field")),
            (500, .server(statusCode: 500, message: "down"))
        ]

        for (statusCode, expected) in cases {
            let client = try makeClient(token: "token")
            let message = expectedMessage(expected)
            TestURLProtocol.handler = { _ in
                .json(statusCode: statusCode, object: ["detail": message])
            }
            let request = APIRequest<RemoteHealthDTO>(method: .get, path: "/health", authentication: .public)

            do {
                _ = try await client.send(request)
                XCTFail("Expected HTTP \(statusCode) to fail")
            } catch let error as APIError {
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
        } catch let error as APIError {
            guard case .decoding = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testTransportFailureIsReportedWithoutChangingAuthentication() async throws {
        let client = try makeClient(token: nil)
        TestURLProtocol.handler = { _ in .failure(URLError(.cannotConnectToHost)) }

        do {
            _ = try await client.send(APIRequest<RemoteHealthDTO>(method: .get, path: "/health", authentication: .public))
            XCTFail("Expected transport failure")
        } catch let error as APIError {
            guard case .transport = error else { return XCTFail("Unexpected error: \(error)") }
        }
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
        let configuration = try APIConfiguration(baseURLString: "https://api.example.test")
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [TestURLProtocol.self]
        let provider = token.map(TestTokenProvider.init(token:))
        return APIClient(
            configuration: configuration,
            session: URLSession(configuration: sessionConfiguration),
            tokenProvider: provider
        )
    }

    private func expectedMessage(_ error: APIError) -> String {
        switch error {
        case let .unauthorized(message), let .forbidden(message), let .notFound(message), let .validation(message):
            return message ?? ""
        case let .server(_, message): return message ?? ""
        default: return ""
        }
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

private final class TestURLProtocol: URLProtocol {
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

        static func raw(statusCode: Int, data: Data) -> Result {
            Result(statusCode: statusCode, data: data, headers: [:], error: nil)
        }

        static func failure(_ error: Error) -> Result {
            Result(statusCode: 0, data: Data(), headers: [:], error: error)
        }
    }

    static var handler: ((URLRequest) -> Result)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
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
