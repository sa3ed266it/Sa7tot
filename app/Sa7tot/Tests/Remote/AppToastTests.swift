import XCTest

@MainActor
final class AppToastTests: XCTestCase {
    func testShowExpenseSetsCurrentToast() {
        let coordinator = AppToastCoordinator(visibleDuration: 60, feedbackEnabled: false)

        coordinator.show(kind: .expenseAdded, amount: "-€12.50")

        XCTAssertEqual(coordinator.current?.kind, .expenseAdded)
        XCTAssertEqual(coordinator.current?.title, AppLocalization.string("toast.movement.expenseAdded"))
        XCTAssertEqual(coordinator.current?.amount, "-€12.50")
    }

    func testShowIncomeSetsCurrentToast() {
        let coordinator = AppToastCoordinator(visibleDuration: 60, feedbackEnabled: false)

        coordinator.show(kind: .incomeAdded, amount: "+€50.00")

        XCTAssertEqual(coordinator.current?.kind, .incomeAdded)
        XCTAssertEqual(coordinator.current?.title, AppLocalization.string("toast.movement.incomeAdded"))
        XCTAssertEqual(coordinator.current?.amount, "+€50.00")
    }

    func testNewToastReplacesExistingToast() {
        let coordinator = AppToastCoordinator(visibleDuration: 60, feedbackEnabled: false)

        coordinator.show(kind: .expenseAdded, amount: "-€12.50")
        let firstID = coordinator.current?.id
        coordinator.show(kind: .incomeAdded, amount: "+€50.00")

        XCTAssertNotEqual(coordinator.current?.id, firstID)
        XCTAssertEqual(coordinator.current?.kind, .incomeAdded)
    }

    func testStaleDismissalCannotDismissReplacement() async throws {
        let coordinator = AppToastCoordinator(visibleDuration: 0.05, feedbackEnabled: false)

        coordinator.show(kind: .expenseAdded, amount: "-€12.50")
        try await Task.sleep(nanoseconds: 30_000_000)
        coordinator.show(kind: .incomeAdded, amount: "+€50.00")
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(coordinator.current?.kind, .incomeAdded)

        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertNil(coordinator.current)
    }

    func testAutoDismissClearsCurrentToast() async throws {
        let coordinator = AppToastCoordinator(visibleDuration: 0.01, feedbackEnabled: false)

        coordinator.show(kind: .expenseAdded, amount: "-€12.50")
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertNil(coordinator.current)
    }

    func testManualDismissClearsCurrentToast() {
        let coordinator = AppToastCoordinator(visibleDuration: 60, feedbackEnabled: false)

        coordinator.show(kind: .expenseAdded, amount: "-€12.50")
        coordinator.dismiss()

        XCTAssertNil(coordinator.current)
    }

    func testNoToastExistsWithoutSuccessfulCreationEvent() {
        let coordinator = AppToastCoordinator(visibleDuration: 60, feedbackEnabled: false)

        XCTAssertNil(coordinator.current)
    }

    func testShowErrorToastSetsCurrentToastWithTitleAndMessage() {
        let coordinator = AppToastCoordinator(visibleDuration: 60, feedbackEnabled: false)

        coordinator.showError(titleKey: "error.mutation.delete.title", error: .connectionFailed)

        XCTAssertEqual(coordinator.current?.kind, .error(titleKey: "error.mutation.delete.title", messageKey: "error.blocking.connection.message"))
        XCTAssertEqual(coordinator.current?.title, AppLocalization.string("error.mutation.delete.title"))
        XCTAssertEqual(coordinator.current?.message, AppLocalization.string("error.blocking.connection.message"))
    }
}
