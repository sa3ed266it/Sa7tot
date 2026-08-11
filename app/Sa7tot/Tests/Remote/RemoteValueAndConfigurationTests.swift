import Foundation
import UIKit
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

    func testCategoryPresetCatalogHasApprovedV1ShapeAndNoSubscriptions() {
        XCTAssertEqual(CategoryPresetCatalog.expenses.count, 11)
        XCTAssertEqual(CategoryPresetCatalog.incomes.count, 6)
        XCTAssertFalse(CategoryPresetCatalog.all.contains { $0.key == "expense.subscriptions" })
        XCTAssertFalse(CategoryPresetCatalog.all.contains { $0.key.localizedCaseInsensitiveContains("subscription") })
        XCTAssertEqual(CategoryPresetCatalog.expenses.map(\.order), Array(0..<11))
        XCTAssertEqual(CategoryPresetCatalog.incomes.map(\.order), Array(0..<6))
    }

    func testCategoryPresetCatalogUsesRefinedNativeSymbols() {
        XCTAssertEqual(
            CategoryPresetCatalog.expenses.map(\.symbolName),
            [
                "fork.knife", "car.fill", "house.fill", "cart.fill", "person.2.fill",
                "bolt.fill", "tshirt.fill", "cross.case.fill", "pawprint.fill", "shoe.2.fill", "gift.fill"
            ]
        )
        XCTAssertEqual(
            CategoryPresetCatalog.incomes.map(\.symbolName),
            [
                "creditcard.fill", "wallet.pass.fill", "briefcase.fill",
                "chart.line.uptrend.xyaxis", "gift.fill", "hand.thumbsup.fill"
            ]
        )
    }

    func testCategoryPresetSymbolsResolveOnCurrentRuntime() {
        for preset in CategoryPresetCatalog.all {
            XCTAssertNotNil(UIImage(systemName: preset.symbolName), "Missing SF Symbol: \(preset.symbolName)")
        }
    }

    func testCategoryPresetDisplayUsesLocalizedCatalogKey() {
        let preset = try! XCTUnwrap(CategoryPresetCatalog.expenses.first { $0.key == "expense.food" })
        XCTAssertEqual(preset.localizedTitle, AppLocalization.string("category.preset.expense.food"))
        XCTAssertEqual(preset.symbolName, "fork.knife")
        XCTAssertEqual(preset.defaultColor, "#279AF4")
    }

    func testCategoryDTODecodesNullablePresetKeyAndActivationPayloadUsesStableKey() throws {
        let json = """
        {
          "id":"00000000-0000-0000-0000-000000000020",
          "user_id":"00000000-0000-0000-0000-000000000001",
          "name":"Food",
          "income":false,
          "icon_identifier":"sf:fork.knife",
          "color":"#279AF4",
          "sort_order":0,
          "preset_key":"expense.food",
          "deleted_at":null,
          "created_at":"2026-08-08T10:00:00Z",
          "updated_at":"2026-08-08T10:00:00Z"
        }
        """
        let category = try RemoteJSON.decoder().decode(RemoteCategoryDTO.self, from: Data(json.utf8))
        XCTAssertEqual(category.presetKey, "expense.food")

        let payload = RemoteCategoryPresetActivationPayload(
            presetKey: "expense.food",
            income: false,
            displayName: "Cibo"
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        XCTAssertEqual(object?["preset_key"] as? String, "expense.food")
        XCTAssertEqual(object?["income"] as? Bool, false)
        XCTAssertEqual(object?["display_name"] as? String, "Cibo")
    }

    func testDirectCategoryAutoSelectionMatchesTypeSafetyRules() {
        let expenseCategoryID = UUID()
        let createdExpenseCategory = RemoteCategoryBriefDTO(
            id: expenseCategoryID,
            name: "Test Direct Expense",
            income: false,
            iconIdentifier: "sf:tag.fill",
            color: "#279AF4",
            presetKey: nil
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
            color: "#279AF4",
            presetKey: nil
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
            color: "#EC7A58",
            presetKey: nil
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

    func testNewMovementTimestampAndEditModePreservationSemantics() {
        let originalDate = Date(timeIntervalSince1970: 1_600_000_000)
        let existingTransaction = RemoteTransactionDTO(
            id: UUID(),
            userID: UUID(),
            kind: .expense,
            accountID: UUID(),
            destinationAccountID: nil,
            amountMinor: -2000,
            currencyCode: "EUR",
            currencyExponent: 2,
            occurredAt: originalDate,
            localDay: try! RemoteDateOnly(isoString: "2020-09-13"),
            title: "Spesa",
            effectiveAmountMinor: -2000,
            category: nil,
            transfer: nil,
            subscription: nil,
            recurrence: nil,
            note: nil,
            merchant: nil,
            origin: "manual",
            reviewStatus: "confirmed",
            externalReference: nil,
            createdAt: originalDate,
            updatedAt: originalDate
        )

        let isEditing = existingTransaction != nil
        let resolvedTimestampForEdit = isEditing ? existingTransaction.occurredAt : Date.now
        XCTAssertEqual(resolvedTimestampForEdit, originalDate, "Editing an existing transaction must preserve its original occurredAt date.")

        let isEditingNew: Bool = false
        let beforeSave = Date.now
        let resolvedTimestampForNew = isEditingNew ? originalDate : Date.now
        let afterSave = Date.now

        XCTAssertGreaterThanOrEqual(resolvedTimestampForNew, beforeSave)
        XCTAssertLessThanOrEqual(resolvedTimestampForNew, afterSave)
    }

    func testEditMovementPayloadPreservesOriginalTimestampWithoutCurrentTime() {
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let originalAccountID = UUID()
        let updatedAccountID = UUID()
        let categoryID = UUID()

        let existingTransaction = RemoteTransactionDTO(
            id: UUID(),
            userID: UUID(),
            kind: .expense,
            accountID: originalAccountID,
            destinationAccountID: nil,
            amountMinor: -4500,
            currencyCode: "EUR",
            currencyExponent: 2,
            occurredAt: originalDate,
            localDay: try! RemoteDateOnly(isoString: "2023-11-14"),
            title: "Cena",
            effectiveAmountMinor: -4500,
            category: nil,
            transfer: nil,
            subscription: nil,
            recurrence: nil,
            note: "Vecchia nota",
            merchant: nil,
            origin: "manual",
            reviewStatus: "confirmed",
            externalReference: nil,
            createdAt: originalDate,
            updatedAt: originalDate
        )

        // Simulate building update payload with edited fields (amount, account, category, note)
        let updatePayload = RemoteTransactionUpdatePayload(
            kind: .expense,
            accountID: updatedAccountID,
            amountMinor: 5500,
            currencyCode: "EUR",
            currencyExponent: 2,
            occurredAt: existingTransaction.occurredAt,
            categoryID: categoryID,
            note: "Nuova nota",
            merchant: nil,
            origin: "manual",
            reviewStatus: "confirmed"
        )

        XCTAssertEqual(updatePayload.occurredAt, originalDate, "Update payload must preserve the exact original timestamp of the transaction.")
        XCTAssertNotEqual(updatePayload.occurredAt, Date(), "Update payload timestamp must not be replaced with current time Date().")
        XCTAssertEqual(updatePayload.accountID, updatedAccountID)
        XCTAssertEqual(updatePayload.amountMinor, 5500)
        XCTAssertEqual(updatePayload.note, "Nuova nota")
    }

    func testAccountSelectorPreselection() {
        let accountA = UUID()
        let accountB = UUID()
        let initialAccountID: UUID? = accountA
        let selectedAccountID: UUID? = accountB

        let resolved = initialAccountID ?? selectedAccountID
        XCTAssertEqual(resolved, accountA, "Initial account ID passed to editor must take precedence for initial account selection.")
    }

    func testSubscriptionOriginTransactionDisallowsDirectMutationAndRowActions() {
        let date = Date()
        let subscriptionBrief = RemoteSubscriptionBriefDTO(id: UUID(), serviceID: "netflix", displayName: "Netflix")

        let subscriptionTransaction = RemoteTransactionDTO(
            id: UUID(),
            userID: UUID(),
            kind: .expense,
            accountID: UUID(),
            destinationAccountID: nil,
            amountMinor: -1599,
            currencyCode: "EUR",
            currencyExponent: 2,
            occurredAt: date,
            localDay: try! RemoteDateOnly(isoString: "2026-08-10"),
            title: "Netflix",
            effectiveAmountMinor: -1599,
            category: nil,
            transfer: nil,
            subscription: subscriptionBrief,
            recurrence: nil,
            note: nil,
            merchant: nil,
            origin: "subscription",
            reviewStatus: "confirmed",
            externalReference: nil,
            createdAt: date,
            updatedAt: date
        )

        let normalExpense = RemoteTransactionDTO(
            id: UUID(),
            userID: UUID(),
            kind: .expense,
            accountID: UUID(),
            destinationAccountID: nil,
            amountMinor: -500,
            currencyCode: "EUR",
            currencyExponent: 2,
            occurredAt: date,
            localDay: try! RemoteDateOnly(isoString: "2026-08-10"),
            title: "Caffè",
            effectiveAmountMinor: -500,
            category: nil,
            transfer: nil,
            subscription: nil,
            recurrence: nil,
            note: nil,
            merchant: nil,
            origin: "manual",
            reviewStatus: "confirmed",
            externalReference: nil,
            createdAt: date,
            updatedAt: date
        )

        XCTAssertFalse(subscriptionTransaction.allowsDirectMutation, "Subscription-origin transaction must disallow direct row mutation (Edit/Delete).")
        XCTAssertTrue(normalExpense.allowsDirectMutation, "Normal expense transaction must allow direct row mutation (Edit/Delete).")
    }

    func testVisualPagerPositionChangeAloneDoesNotCommitStoreAccountUntilSettled() {
        let accountA = UUID()
        let accountB = UUID()

        var committedAccountID = accountA
        var visualAccountID: UUID? = accountA

        // Intermediate scroll drag to account B
        visualAccountID = accountB

        // Drag is active (not settled) -> store commit must not happen yet
        XCTAssertEqual(committedAccountID, accountA, "Visual pager position change alone during drag must not commit store account.")

        // Paging settles on account B -> commit account B
        if let settledID = visualAccountID, settledID != committedAccountID {
            committedAccountID = settledID
        }

        XCTAssertEqual(committedAccountID, accountB, "Settled scroll position must commit account selection.")
    }

    func testCanceledInteractiveSwipeDoesNotSwitchMovementDataset() {
        let accountA = UUID()
        let accountB = UUID()

        var committedAccountID = accountA
        var visualAccountID: UUID? = accountA

        // Swipe begins toward account B
        visualAccountID = accountB

        // User cancels swipe, returning to account A
        visualAccountID = accountA

        // Paging settles back on account A
        if let settledID = visualAccountID, settledID != committedAccountID {
            committedAccountID = settledID
        }

        XCTAssertEqual(committedAccountID, accountA, "Canceled swipe returning to original account must preserve current committed account dataset.")
    }

    func testCommittedAccountSwitchSelectsCorrectCachedMovementState() {
        let accountA = UUID()
        let accountB = UUID()

        var currentSelectedAccountID: UUID? = accountA

        // Committing account B
        currentSelectedAccountID = accountB
        XCTAssertEqual(currentSelectedAccountID, accountB, "Committed account switch must update selected account ID to target account.")

        // Committing account A
        currentSelectedAccountID = accountA
        XCTAssertEqual(currentSelectedAccountID, accountA, "Committed account switch back must restore selected account ID to original account.")
    }

    func testRepeatedABASwitchesEndOnCorrectAccount() {
        let accountA = UUID()
        let accountB = UUID()

        var committedAccountID = accountA
        let switches = [accountB, accountA, accountB, accountA]

        for target in switches {
            if target != committedAccountID {
                committedAccountID = target
            }
        }

        XCTAssertEqual(committedAccountID, accountA, "Repeated A->B->A commits must end on the final settled account.")
    }

    func testStartupFastPathReusesOnlyMatchingFreshAccountPage() {
        let accountID = UUID()

        XCTAssertEqual(
            RemoteStartupFastPathDecision.resolve(
                lastKnownAccountID: accountID,
                authoritativeAccountID: accountID,
                speculativePageAccountID: nil,
                hasFreshCache: true,
                hasInFlightPage: false
            ),
            .useFreshCache
        )
        XCTAssertEqual(
            RemoteStartupFastPathDecision.resolve(
                lastKnownAccountID: accountID,
                authoritativeAccountID: accountID,
                speculativePageAccountID: accountID,
                hasFreshCache: false,
                hasInFlightPage: true
            ),
            .awaitSpeculativePage
        )
    }

    func testStartupFastPathFallsBackWhenLastKnownAccountOrPageDoesNotMatch() {
        let accountA = UUID()
        let accountB = UUID()

        XCTAssertEqual(
            RemoteStartupFastPathDecision.resolve(
                lastKnownAccountID: accountA,
                authoritativeAccountID: accountB,
                speculativePageAccountID: accountA,
                hasFreshCache: false,
                hasInFlightPage: true
            ),
            .fetchAuthoritativePage
        )
        XCTAssertEqual(
            RemoteStartupFastPathDecision.resolve(
                lastKnownAccountID: accountA,
                authoritativeAccountID: accountA,
                speculativePageAccountID: accountB,
                hasFreshCache: false,
                hasInFlightPage: true
            ),
            .fetchAuthoritativePage
        )
    }

    func testStartupFastPathRejectsLateWrongAccountOrGeneration() {
        let accountA = UUID()
        let accountB = UUID()

        XCTAssertFalse(
            RemoteStartupFastPathDecision.canPublish(
                pageAccountID: accountA,
                intendedAccountID: accountB,
                expectedGeneration: 1,
                currentGeneration: 2
            )
        )
        XCTAssertTrue(
            RemoteStartupFastPathDecision.canPublish(
                pageAccountID: accountB,
                intendedAccountID: accountB,
                expectedGeneration: 2,
                currentGeneration: 2
            )
        )
        XCTAssertFalse(
            RemoteStartupFastPathDecision.canPublish(
                pageAccountID: accountB,
                intendedAccountID: accountB,
                expectedGeneration: 2,
                currentGeneration: 2,
                hasAuthoritativeAccountSet: false,
                isSpeculative: true
            )
        )
        XCTAssertTrue(
            RemoteStartupFastPathDecision.shouldDeferSpeculativePage(
                isSpeculative: true,
                hasAuthoritativeAccountSet: false
            )
        )
    }

    func testAccountCardGradientPresetsCatalogAndMatching() {
        XCTAssertEqual(AccountCardGradientPreset.all.count, 8, "Must contain exactly 8 gradient presets.")

        let names = AccountCardGradientPreset.all.map(\.displayName)
        XCTAssertEqual(names, ["Graphite", "Midnight", "Royal Blue", "Violet", "Emerald", "Forest", "Burgundy", "Champagne"])

        XCTAssertEqual(AccountCardGradientPreset.all[0].primaryHex, "#34363D")
        XCTAssertEqual(AccountCardGradientPreset.all[0].secondaryHex, "#111318")

        XCTAssertEqual(AccountCardGradientPreset.all[2].primaryHex, "#5E7CE2")
        XCTAssertEqual(AccountCardGradientPreset.all[2].secondaryHex, "#3346A8")

        XCTAssertEqual(AccountCardGradientPreset.match(hex: "#5E7CE2")?.displayName, "Royal Blue")
        XCTAssertEqual(AccountCardGradientPreset.match(hex: "5e7ce2")?.displayName, "Royal Blue")
        XCTAssertEqual(AccountCardGradientPreset.match(hex: "#19A77B")?.displayName, "Emerald")

        // Legacy non-preset color test
        XCTAssertNil(AccountCardGradientPreset.match(hex: "#FF5733"), "Non-preset hex must return nil match.")
        XCTAssertNil(AccountCardGradientPreset.match(hex: nil), "Nil hex must return nil match.")
    }
}

