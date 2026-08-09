import Foundation
import XCTest

final class RemoteValueAndConfigurationTests: XCTestCase {
    func testDateOnlyNeverUsesMidnightUTCConversion() throws {
        let date = try RemoteDateOnly(isoString: "2026-02-28")
        XCTAssertEqual(date.isoString, "2026-02-28")
        XCTAssertEqual(try RemoteJSON.decoder().decode(RemoteDateOnly.self, from: Data("\"2026-02-28\"".utf8)), date)
        XCTAssertThrowsError(try RemoteDateOnly(isoString: "2026-02-30"))
    }

    func testConfigurationNormalizesSupportedPostgresIndependentAPIURL() throws {
        let configuration = try APIConfiguration(baseURLString: "https://api.example.test/v1")
        let url = try configuration.url(path: "/health", queryItems: [URLQueryItem(name: "check", value: "true")])
        XCTAssertEqual(url.absoluteString, "https://api.example.test/v1/health?check=true")
    }

    func testDebugConfigurationUsesLoopbackDefaultWhenBundleValueIsMissing() throws {
        let configuration = try APIConfiguration.current(bundle: Bundle(for: Self.self), environment: [:])
        #if DEBUG
        XCTAssertEqual(configuration.baseURL.absoluteString, "http://127.0.0.1:8000/")
        #else
        XCTSkip("The production configuration intentionally requires an explicit API_BASE_URL.")
        #endif
    }

    func testConfigurationRejectsCredentialsAndUnsupportedSchemes() {
        XCTAssertThrowsError(try APIConfiguration(baseURLString: "ftp://api.example.test"))
        XCTAssertThrowsError(try APIConfiguration(baseURLString: "https://user:password@api.example.test"))
        XCTAssertThrowsError(try APIConfiguration(baseURLString: nil))
    }
}
