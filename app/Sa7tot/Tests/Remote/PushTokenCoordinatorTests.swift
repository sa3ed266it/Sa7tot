import Foundation
import XCTest

@MainActor
final class PushTokenCoordinatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(TestPushURLProtocol.self)
    }

    override func tearDown() {
        TestPushURLProtocol.handler = nil
        URLProtocol.unregisterClass(TestPushURLProtocol.self)
        super.tearDown()
    }

    func testDeviceTokenIsLowercaseHexadecimal() {
        XCTAssertEqual(
            PushTokenCoordinator.hexadecimalToken(from: Data([0x00, 0xAB, 0xFF, 0x10])),
            "00abff10"
        )
    }

    func testRegistrationPayloadUsesBackendCodingKeys() throws {
        let payload = RemotePushDeviceRegistrationPayload(
            token: "00abff10",
            environment: .development,
            appVersion: "2.1.4"
        )

        let data = try RemoteJSON.encoder().encode(payload)
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["token"] as? String, "00abff10")
        XCTAssertEqual(object["platform"] as? String, "ios")
        XCTAssertEqual(object["environment"] as? String, "development")
        XCTAssertEqual(object["app_version"] as? String, "2.1.4")
    }

    @MainActor
    func testRestoresPersistedTokenForSignOutAfterCoordinatorRecreation() {
        let defaults = makeTestDefaults()
        defaults.set("00abff10", forKey: "push.apnsToken")

        let coordinator = PushTokenCoordinator(
            client: nil,
            tokenProvider: nil,
            defaults: defaults
        )

        XCTAssertEqual(coordinator.apnsToken, "00abff10")
    }

    @MainActor
    func testSignOutLifecycleRunsDeactivationBeforeSessionClear() async {
        var events: [String] = []

        let didSignOut = await PushSignOutLifecycle.run(
            deactivate: {
                events.append("deactivate")
            },
            signOut: {
                XCTAssertEqual(events, ["deactivate"])
                events.append("signOut")
            }
        )

        XCTAssertTrue(didSignOut)
        XCTAssertEqual(events, ["deactivate", "signOut"])
    }

    @MainActor
    func testSignOutLifecycleDoesNotClearSessionWhenDeactivationFails() async {
        var didClearSession = false

        let didSignOut = await PushSignOutLifecycle.run(
            deactivate: {
                throw TestPushError.deactivationFailed
            },
            signOut: {
                didClearSession = true
            }
        )

        XCTAssertFalse(didSignOut)
        XCTAssertFalse(didClearSession)
    }

    @MainActor
    func testNoAuthenticatedUserSkipsDeactivationRequest() async throws {
        let defaults = makeTestDefaults()
        defaults.set("00abff10", forKey: "push.apnsToken")
        let coordinator = PushTokenCoordinator(
            client: try makeClient(token: "unused"),
            tokenProvider: TestPushTokenProvider(),
            defaults: defaults
        )

        TestPushURLProtocol.handler = { _ in
            XCTFail("No deactivation request should be attempted without an authenticated user")
            return .json(statusCode: 200, object: ["deactivated": true])
        }

        try await coordinator.deactivateCurrentRegistration()
    }

    @MainActor
    func testAuthenticatedDeactivationUsesPersistedTokenAndAuthSession() async throws {
        let defaults = makeTestDefaults()
        defaults.set("00abff10", forKey: "push.apnsToken")
        let client = try makeClient(token: "test-jwt")
        let coordinator = PushTokenCoordinator(
            client: client,
            tokenProvider: TestPushTokenProvider(),
            defaults: defaults
        )
        let session = SupabaseAuthSession(
            accessToken: "test-jwt",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSinceNow: 3600),
            userID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        var requestWasObserved = false
        TestPushURLProtocol.handler = { request in
            requestWasObserved = true
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/v1/push/devices/00abff10")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-jwt")
            return .json(statusCode: 200, object: ["deactivated": true])
        }

        coordinator.reconcile(authState: .signedIn(session))
        try await coordinator.deactivateCurrentRegistration()

        XCTAssertTrue(requestWasObserved)
        XCTAssertEqual(coordinator.apnsToken, "00abff10")
        defaults.removePersistentDomain(forName: #function)
    }
}

private enum TestPushError: Error {
    case deactivationFailed
}

private struct TestPushTokenProvider: AuthTokenProvider {
    func accessToken() async throws -> String { "test-jwt" }
    func refreshSession() async throws -> String { "test-jwt" }
}

private extension PushTokenCoordinatorTests {
    func makeTestDefaults() -> UserDefaults {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "push.apnsToken")
        return defaults
    }

    func makeClient(token: String?) throws -> APIClient {
        let configuration = try APIConfiguration(baseURLString: "http://push.example.test")
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [TestPushURLProtocol.self]
        return APIClient(
            configuration: configuration,
            session: URLSession(configuration: sessionConfiguration),
            tokenProvider: token.map { _ in TestPushTokenProvider() }
        )
    }
}

private final class TestPushURLProtocol: URLProtocol {
    struct Result {
        let statusCode: Int
        let data: Data
        let headers: [String: String]

        static func json(statusCode: Int, object: Any) -> Result {
            Result(
                statusCode: statusCode,
                data: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(),
                headers: ["Content-Type": "application/json"]
            )
        }
    }

    static var handler: ((URLRequest) -> Result)?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "push.example.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let result = Self.handler?(request), let response = HTTPURLResponse(
            url: request.url!,
            statusCode: result.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: result.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
