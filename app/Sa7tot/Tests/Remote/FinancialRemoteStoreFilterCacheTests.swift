import Foundation
import XCTest

final class FinancialRemoteStoreFilterCacheTests: XCTestCase {
    @MainActor
    func testReturningToFreshFilterSelectionsUsesRAMCache() async throws {
        let accountID = UUID()
        let profile = try decode(
            RemoteProfileDTO.self,
            [
                "user_id": UUID().uuidString,
                "locale": "en-US",
                "timezone": "Europe/Rome",
                "default_currency_code": "EUR",
                "month_start_day": 1,
                "week_start_day": 1
            ]
        )
        let account = try decode(
            RemoteAccountDTO.self,
            [
                "id": accountID.uuidString,
                "user_id": profile.userID.uuidString,
                "name": "Main",
                "type": "bank",
                "currency_code": "EUR",
                "currency_exponent": 2,
                "opening_balance_minor": 0,
                "icon_name": "building.columns.fill",
                "color": "#5E7CE2",
                "is_archived": false,
                "sort_order": 0,
                "created_at": "2026-08-11T00:00:00Z",
                "updated_at": "2026-08-11T00:00:00Z"
            ]
        )
        let repository = CountingMovementsRepository(page: try decodePage(accountID: accountID))
        let store = FinancialRemoteStore(
            client: nil,
            movementsRepository: repository,
            initialAccounts: [account],
            initialProfile: profile
        )

        store.selectAccount(accountID)
        try await waitUntil { await repository.requestCount == 1 }

        store.setFilter(.week)
        try await waitUntil { await repository.requestCount == 2 }
        store.moveWeek(by: 1)
        try await waitUntil { await repository.requestCount == 3 }
        store.moveWeek(by: -1)
        await Task.yield()
        let weekRequests = await repository.requestCount
        XCTAssertEqual(weekRequests, 3, "returning to a fresh week must not refetch")

        let categoryA = UUID()
        let categoryB = UUID()
        store.setCategoryFilter(categoryA)
        try await waitUntil { await repository.requestCount == 4 }
        store.setCategoryFilter(categoryB)
        try await waitUntil { await repository.requestCount == 5 }
        store.setCategoryFilter(categoryA)
        await Task.yield()
        let categoryRequests = await repository.requestCount
        XCTAssertEqual(categoryRequests, 5, "returning to a fresh category must not refetch")

        store.setFilter(.month)
        try await waitUntil { await repository.requestCount == 6 }
        store.moveMonth(by: -1)
        try await waitUntil { await repository.requestCount == 7 }
        store.moveMonth(by: 1)
        await Task.yield()
        let monthRequests = await repository.requestCount
        XCTAssertEqual(monthRequests, 7, "returning to a fresh month must not refetch")

        store.typeIsIncome = true
        store.setTypeFilter(previousValue: false)
        try await waitUntil { await repository.requestCount == 8 }
        store.typeIsIncome = false
        store.setTypeFilter(previousValue: true)
        try await waitUntil { await repository.requestCount == 9 }

        store.setFilter(.subscription)
        try await waitUntil { await repository.requestCount == 10 }
        store.setFilter(.all)
        await Task.yield()
        let resetRequests = await repository.requestCount
        XCTAssertEqual(resetRequests, 10, "returning to a fresh all-movements filter must not refetch")
        store.setFilter(.subscription)
        await Task.yield()
        let subscriptionRequests = await repository.requestCount
        XCTAssertEqual(subscriptionRequests, 10, "returning to a fresh subscription filter must not refetch")
    }

    @MainActor
    func testRepeatedCurrentSelectionIsANoop() async throws {
        let accountID = UUID()
        let profile = try decode(
            RemoteProfileDTO.self,
            [
                "user_id": UUID().uuidString,
                "locale": "en-US",
                "timezone": "Europe/Rome",
                "default_currency_code": "EUR"
            ]
        )
        let account = try decode(
            RemoteAccountDTO.self,
            [
                "id": accountID.uuidString,
                "user_id": profile.userID.uuidString,
                "name": "Main",
                "type": "bank",
                "currency_code": "EUR",
                "currency_exponent": 2,
                "opening_balance_minor": 0,
                "icon_name": "building.columns.fill",
                "color": "#5E7CE2",
                "is_archived": false,
                "sort_order": 0,
                "created_at": "2026-08-11T00:00:00Z",
                "updated_at": "2026-08-11T00:00:00Z"
            ]
        )
        let repository = CountingMovementsRepository(page: try decodePage(accountID: accountID))
        let store = FinancialRemoteStore(
            client: nil,
            movementsRepository: repository,
            initialAccounts: [account],
            initialProfile: profile
        )

        store.selectAccount(accountID)
        try await waitUntil { await repository.requestCount == 1 }
        store.setFilter(.week)
        try await waitUntil { await repository.requestCount == 2 }
        store.setFilter(.week)
        store.moveWeek(by: 0)
        await Task.yield()
        var requests = await repository.requestCount
        XCTAssertEqual(requests, 2)

        store.selectMonth(store.selectedMonth)
        try await waitUntil { await repository.requestCount == 3 }
        store.selectMonth(store.selectedMonth)
        await Task.yield()
        requests = await repository.requestCount
        XCTAssertEqual(requests, 3)
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<100 {
            if await condition() {
                try await Task.sleep(nanoseconds: 40_000_000)
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out waiting for the mocked movement request")
    }

    private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try RemoteJSON.decoder().decode(type, from: data)
    }

    private func decodePage(accountID: UUID) throws -> RemoteMovimentiPageDTO {
        let object: [String: Any] = [
            "account": [
                "id": accountID.uuidString,
                "name": "Main",
                "currency_code": "EUR",
                "currency_exponent": 2,
                "balance_minor": 1000
            ],
            "summary": ["income_minor": 1000, "expenses_minor": 0],
            "days": [],
            "next_cursor": NSNull()
        ]
        return try decode(RemoteMovimentiPageDTO.self, object)
    }

    func testCompactAccountIdentityPresetGradientResolution() {
        let presetMatch = AccountCardGradientPreset.match(hex: "#5E7CE2")
        XCTAssertEqual(presetMatch?.id, "royalBlue")

        let customGradient = AccountCardGradientPreset.gradient(forPrimaryHex: "#FF5733")
        XCTAssertNotNil(customGradient)

        let nilGradient = AccountCardGradientPreset.gradient(forPrimaryHex: nil)
        XCTAssertNotNil(nilGradient)
    }

    @MainActor
    func testAsyncPeriodNavigationAwaitsMovementCompletion() async throws {
        let accountID = UUID()
        let profile = try decode(
            RemoteProfileDTO.self,
            [
                "user_id": UUID().uuidString,
                "locale": "en-US",
                "timezone": "Europe/Rome",
                "default_currency_code": "EUR",
                "month_start_day": 1,
                "week_start_day": 1
            ]
        )
        let account = try decode(
            RemoteAccountDTO.self,
            [
                "id": accountID.uuidString,
                "user_id": profile.userID.uuidString,
                "name": "Main",
                "type": "bank",
                "currency_code": "EUR",
                "currency_exponent": 2,
                "opening_balance_minor": 0,
                "icon_name": "building.columns.fill",
                "color": "#5E7CE2",
                "is_archived": false,
                "sort_order": 0,
                "created_at": "2026-08-11T00:00:00Z",
                "updated_at": "2026-08-11T00:00:00Z"
            ]
        )
        let repository = DelayedMovementsRepository(page: try decodePage(accountID: accountID), delayNanoseconds: 50_000_000)
        let store = FinancialRemoteStore(
            client: nil,
            movementsRepository: repository,
            initialAccounts: [account],
            initialProfile: profile
        )

        store.selectAccount(accountID)
        await store.awaitCurrentMovementLoad()

        let initialMonth = store.selectedMonth

        await store.moveMonthAndWait(by: -1)

        XCTAssertEqual(store.filter, .month)
        XCTAssertNotEqual(store.selectedMonth, initialMonth)
        let count = await repository.requestCount
        XCTAssertGreaterThanOrEqual(count, 2, "async period navigation must await the delayed movement request")
    }
}

private actor DelayedMovementsRepository: RemoteMovimentiPageProviding {
    let pageResult: RemoteMovimentiPageDTO
    let delayNanoseconds: UInt64
    private(set) var requestCount = 0

    init(page: RemoteMovimentiPageDTO, delayNanoseconds: UInt64) {
        self.pageResult = page
        self.delayNanoseconds = delayNanoseconds
    }

    func page(
        accountID: UUID,
        limit: Int?,
        cursor: String?,
        filter: String?,
        income: Bool?,
        day: RemoteDateOnly?,
        weekStart: RemoteDateOnly?,
        month: String?,
        categoryID: UUID?
    ) async throws -> RemoteMovimentiPageDTO {
        requestCount += 1
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return pageResult
    }
}

private actor CountingMovementsRepository: RemoteMovimentiPageProviding {
    let pageResult: RemoteMovimentiPageDTO
    private(set) var requestCount = 0

    init(page: RemoteMovimentiPageDTO) {
        pageResult = page
    }

    func page(
        accountID: UUID,
        limit: Int?,
        cursor: String?,
        filter: String?,
        income: Bool?,
        day: RemoteDateOnly?,
        weekStart: RemoteDateOnly?,
        month: String?,
        categoryID: UUID?
    ) async throws -> RemoteMovimentiPageDTO {
        requestCount += 1
        try await Task.sleep(nanoseconds: 20_000_000)
        return pageResult
    }
}
