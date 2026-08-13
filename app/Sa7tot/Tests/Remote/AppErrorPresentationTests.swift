import Foundation
import XCTest

final class AppErrorPresentationTests: XCTestCase {
    func testNetworkUnavailablePresentationKeys() {
        let presentation = AppErrorPresentationPolicy.blockingPresentation(for: .networkUnavailable)
        XCTAssertEqual(presentation.iconName, "wifi.slash")
        XCTAssertEqual(presentation.titleKey, "error.blocking.offline.title")
        XCTAssertEqual(presentation.messageKey, "error.blocking.offline.message")
        XCTAssertEqual(presentation.primaryActionKey, "action.retry")
    }

    func testConnectionFailedPresentationKeys() {
        let presentation = AppErrorPresentationPolicy.blockingPresentation(for: .connectionFailed)
        XCTAssertEqual(presentation.iconName, "exclamationmark.arrow.triangle.2.circlepath")
        XCTAssertEqual(presentation.titleKey, "error.blocking.connection.title")
        XCTAssertEqual(presentation.messageKey, "error.blocking.connection.message")
        XCTAssertEqual(presentation.primaryActionKey, "action.retry")
    }

    func testTimeoutPresentationKeys() {
        let presentation = AppErrorPresentationPolicy.blockingPresentation(for: .timeout)
        XCTAssertEqual(presentation.iconName, "clock.badge.exclamationmark")
        XCTAssertEqual(presentation.titleKey, "error.blocking.timeout.title")
        XCTAssertEqual(presentation.messageKey, "error.blocking.timeout.message")
        XCTAssertEqual(presentation.primaryActionKey, "action.retry")
    }

    func testServerUnavailablePresentationKeys() {
        let presentation = AppErrorPresentationPolicy.blockingPresentation(for: .serverUnavailable(statusCode: 500))
        XCTAssertEqual(presentation.iconName, "server.rack")
        XCTAssertEqual(presentation.titleKey, "error.blocking.server.title")
        XCTAssertEqual(presentation.messageKey, "error.blocking.server.message")
        XCTAssertEqual(presentation.primaryActionKey, "action.retry")
    }

    func testInvalidResponseAndDecodingPresentationKeys() {
        let decodingPresentation = AppErrorPresentationPolicy.blockingPresentation(for: .decoding(details: "bad json"))
        XCTAssertEqual(decodingPresentation.iconName, "exclamationmark.triangle")
        XCTAssertEqual(decodingPresentation.titleKey, "error.blocking.invalidResponse.title")
        XCTAssertEqual(decodingPresentation.messageKey, "error.blocking.invalidResponse.message")
        XCTAssertEqual(decodingPresentation.primaryActionKey, "action.retry")

        let invalidPresentation = AppErrorPresentationPolicy.blockingPresentation(for: .invalidResponse)
        XCTAssertEqual(invalidPresentation.iconName, "exclamationmark.triangle")
        XCTAssertEqual(invalidPresentation.titleKey, "error.blocking.invalidResponse.title")
        XCTAssertEqual(invalidPresentation.messageKey, "error.blocking.invalidResponse.message")
        XCTAssertEqual(invalidPresentation.primaryActionKey, "action.retry")
    }

    func testForbiddenPresentationKeys() {
        let presentation = AppErrorPresentationPolicy.blockingPresentation(for: .forbidden)
        XCTAssertEqual(presentation.iconName, "lock.slash")
        XCTAssertEqual(presentation.titleKey, "error.blocking.forbidden.title")
        XCTAssertEqual(presentation.messageKey, "error.blocking.forbidden.message")
        XCTAssertEqual(presentation.primaryActionKey, "action.retry")
    }

    func testGenericPresentationKeys() {
        let cases: [AppError] = [
            .unauthorized,
            .configuration,
            .unknown(message: "mystery error")
        ]

        for errorCase in cases {
            let presentation = AppErrorPresentationPolicy.blockingPresentation(for: errorCase)
            XCTAssertEqual(presentation.iconName, "exclamationmark.triangle")
            XCTAssertEqual(presentation.titleKey, "error.blocking.generic.title")
            XCTAssertEqual(presentation.messageKey, "error.blocking.generic.message")
            XCTAssertEqual(presentation.primaryActionKey, "action.retry")
        }
    }
}
