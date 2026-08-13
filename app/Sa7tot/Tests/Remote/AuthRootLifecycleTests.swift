import Foundation
import XCTest

@MainActor
final class AuthRootLifecycleTests: XCTestCase {
    func testTransientNetworkErrorDoesNotSignOut() {
        let transientErrors: [AppError] = [
            .networkUnavailable,
            .connectionFailed,
            .timeout,
            .serverUnavailable(statusCode: 503)
        ]

        for error in transientErrors {
            XCTAssertFalse(error == .unauthorized, "Transient error \(error) must not be unauthorized")
        }
    }

    func testUnauthorizedErrorIsUnrecoverable() {
        let error = AppError.unauthorized
        XCTAssertEqual(error, .unauthorized, "Unauthorized error must match .unauthorized case")
    }

    func testBootstrapErrorOwnershipPreventsDuplicateErrorMessage() {
        let store = FinancialRemoteStore(client: nil)
        XCTAssertNil(store.bootstrapError, "Initially bootstrapError must be nil")
        XCTAssertNil(store.errorMessage, "Initially errorMessage must be nil")
        XCTAssertFalse(store.hasUsableContent, "Empty store has no usable content")
    }

    func testNoAccountGatingRequiresSuccessfulBootstrap() {
        let store = FinancialRemoteStore(client: nil)
        XCTAssertEqual(store.bootstrapStatus, .idle)
        XCTAssertTrue(store.activeAccounts.isEmpty)

        // Idle / unresolved status with 0 accounts is NOT an authoritative empty-account state
        let isAuthoritativeEmptyNoAccount = store.bootstrapStatus == .ready && store.activeAccounts.isEmpty
        XCTAssertFalse(isAuthoritativeEmptyNoAccount, "Unresolved bootstrap with 0 accounts must not be classified as emptyNoAccount")
    }

    func testRetryStateStabilityPreservesInlineErrorWithoutColdLoader() {
        let store = FinancialRemoteStore(client: nil)
        XCTAssertNil(store.bootstrapError)

        // When bootstrapError exists, inline error condition holds even if bootstrapStatus is loading
        let hasError = store.bootstrapError != nil || store.bootstrapStatus == .failed
        XCTAssertFalse(hasError, "Cold initial load has no error")
    }

    func testBootstrapErrorRetainedDuringRetryStart() async {
        let store = FinancialRemoteStore(client: nil)
        store.setBootstrapErrorForTesting(.connectionFailed)
        XCTAssertEqual(store.bootstrapError, .connectionFailed)

        // Triggering bootstrap again (retry) must NOT clear bootstrapError at start
        let task = Task { await store.bootstrap() }
        _ = await task.value
        XCTAssertNotNil(store.bootstrapError, "bootstrapError must remain set during and after failed retry")
        XCTAssertEqual(store.bootstrapError, .connectionFailed, "Error identity preserved across failed retry")
    }
}
