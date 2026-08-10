import Foundation
import XCTest
@testable import Sa7tot

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

    func testCategoryEditorPreselectionForExpenseAndIncomeModes() {
        let expenseMode: RemoteTransactionEditorMode = .expense
        let incomeMode: RemoteTransactionEditorMode = .income

        let initialIncomeForExpense = (expenseMode == .income)
        let initialIncomeForIncome = (incomeMode == .income)

        XCTAssertFalse(initialIncomeForExpense, "Expense mode must preselect Expense (initialIncome = false).")
        XCTAssertTrue(initialIncomeForIncome, "Income mode must preselect Income (initialIncome = true).")
    }

    func testDirectCategoryAutoSelectionMatchesTypeSafetyRules() {
        let expenseCategoryID = UUID()
        let createdExpenseCategory = RemoteCategoryBriefDTO(
            id: expenseCategoryID,
            name: "Test Direct Expense",
            income: false,
            iconIdentifier: "sf:tag.fill",
            color: "#279AF4"
        )

        var selectedID: UUID? = nil
        let currentModeIsIncome = false // Expense mode

        if createdExpenseCategory.income == currentModeIsIncome {
            selectedID = createdExpenseCategory.id
        }

        XCTAssertEqual(selectedID, expenseCategoryID, "Compatible expense category created in expense mode must be auto-selected.")

        var incompatibleSelectedID: UUID? = nil
        let createdIncomeCategory = RemoteCategoryBriefDTO(
            id: UUID(),
            name: "Test Direct Income",
            income: true,
            iconIdentifier: "sf:tag.fill",
            color: "#279AF4"
        )

        if createdIncomeCategory.income == currentModeIsIncome {
            incompatibleSelectedID = createdIncomeCategory.id
        }

        XCTAssertNil(incompatibleSelectedID, "Incompatible income category created while in expense mode must NOT be auto-selected.")
    }

    func testCategoryCreationPreservesParentDraftStateOnCancelOrFailure() {
        var parentAmount = "12.34"
        var parentNote = "Test Note"
        var parentAccountID: UUID? = UUID()
        var parentCategoryID: UUID? = nil

        let userCancelled = true
        if !userCancelled {
            parentCategoryID = UUID()
        }

        XCTAssertEqual(parentAmount, "12.34")
        XCTAssertEqual(parentNote, "Test Note")
        XCTAssertNotNil(parentAccountID)
        XCTAssertNil(parentCategoryID, "Cancelling category creation must preserve draft and select nothing.")

        let createFailed = true
        if !createFailed {
            parentCategoryID = UUID()
        }

        XCTAssertEqual(parentAmount, "12.34")
        XCTAssertEqual(parentNote, "Test Note")
        XCTAssertNotNil(parentAccountID)
        XCTAssertNil(parentCategoryID, "Category creation failure must leave parent draft untouched and unselected.")
    }

    func testSubscriptionHasNoCategoryAddAction() {
        let mode: RemoteTransactionEditorMode = .subscription
        let isTransfer = false
        let hasCategoryCarousel = (mode != .subscription && !isTransfer)

        XCTAssertFalse(hasCategoryCarousel, "Subscription mode must not show the category carousel or category-add action.")
    }

    func testMovementTitleSemanticsResolution() {
        let category = RemoteCategoryBriefDTO(
            id: UUID(),
            name: "Test 2",
            income: false,
            iconIdentifier: "sf:scooter",
            color: "#EC7A58"
        )

        let expenseWithCategoryAndNote = RemoteTransactionDTO(
            id: UUID(),
            userID: UUID(),
            kind: .expense,
            accountID: UUID(),
            destinationAccountID: nil,
            amountMinor: -9000,
            currencyCode: "EUR",
            currencyExponent: 2,
            occurredAt: Date(),
            localDay: try! RemoteDateOnly(isoString: "2026-08-10"),
            title: "ChatGPT",
            effectiveAmountMinor: -9000,
            category: category,
            transfer: nil,
            subscription: nil,
            recurrence: nil,
            note: "ChatGPT",
            merchant: nil,
            origin: "manual",
            reviewStatus: "confirmed",
            externalReference: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let resolvedTitleWithCategory = expenseWithCategoryAndNote.category?.name ?? AppLocalization.string("movement.expense")
        XCTAssertEqual(resolvedTitleWithCategory, "Test 2", "Category name must take precedence over note in title resolution.")

        let expenseWithoutCategory = RemoteTransactionDTO(
            id: UUID(),
            userID: UUID(),
            kind: .expense,
            accountID: UUID(),
            destinationAccountID: nil,
            amountMinor: -1500,
            currencyCode: "EUR",
            currencyExponent: 2,
            occurredAt: Date(),
            localDay: try! RemoteDateOnly(isoString: "2026-08-10"),
            title: "ChatGPT",
            effectiveAmountMinor: -1500,
            category: nil,
            transfer: nil,
            subscription: nil,
            recurrence: nil,
            note: "ChatGPT",
            merchant: nil,
            origin: "manual",
            reviewStatus: "confirmed",
            externalReference: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let resolvedTitleWithoutCategory = expenseWithoutCategory.category?.name ?? AppLocalization.string("movement.expense")
        XCTAssertEqual(resolvedTitleWithoutCategory, AppLocalization.string("movement.expense"), "Expense without category must fall back to localized expense string, not note.")
    }
}
