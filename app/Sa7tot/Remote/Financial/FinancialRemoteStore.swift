import Combine
import Foundation

enum RemoteMovementFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case type
    case day
    case week
    case month
    case category
    case subscription
    case recurring
    case upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return AppLocalization.string("filter.all")
        case .type: return AppLocalization.string("filter.type")
        case .day: return AppLocalization.string("filter.day")
        case .week: return AppLocalization.string("filter.week")
        case .month: return AppLocalization.string("filter.month")
        case .category: return AppLocalization.string("filter.category")
        case .subscription: return AppLocalization.string("subscription.title")
        case .recurring: return AppLocalization.string("filter.recurring")
        case .upcoming: return AppLocalization.string("filter.upcoming")
        }
    }
}

struct FinancialPeriodWindow: Equatable {
    let start: Date
    let end: Date
}

enum FinancialPeriodNavigator {
    static let fallbackTimeZone = "Europe/Rome"

    static func calendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: fallbackTimeZone)!
        calendar.locale = .current
        return calendar
    }

    static func weekStart(for date: Date, weekStartDay: Int, timeZoneIdentifier: String) -> Date {
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        let localDate = localDate(for: date, calendar: calendar)
        let weekday = calendar.component(.weekday, from: localDate)
        let isoWeekday = weekday == 1 ? 7 : weekday - 1
        let offset = (isoWeekday - weekStartDay + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: localDate) ?? localDate
    }

    static func weekWindow(for date: Date, weekStartDay: Int, timeZoneIdentifier: String) -> FinancialPeriodWindow {
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        let start = weekStart(for: date, weekStartDay: weekStartDay, timeZoneIdentifier: timeZoneIdentifier)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return FinancialPeriodWindow(start: start, end: end)
    }

    static func shiftedWeek(from date: Date, by offset: Int, weekStartDay: Int, timeZoneIdentifier: String) -> Date {
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        let start = weekStart(for: date, weekStartDay: weekStartDay, timeZoneIdentifier: timeZoneIdentifier)
        return calendar.date(byAdding: .day, value: offset * 7, to: start) ?? start
    }

    static func monthStart(forDisplayYear year: Int, month: Int, monthStartDay: Int, timeZoneIdentifier: String) -> Date {
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        let firstOfMonth = makeDate(year: year, month: month, day: 1, calendar: calendar)
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? monthStartDay
        return makeDate(year: year, month: month, day: min(max(monthStartDay, 1), daysInMonth), calendar: calendar)
    }

    static func financialMonthStart(for date: Date, monthStartDay: Int, timeZoneIdentifier: String) -> Date {
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        let localDate = localDate(for: date, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day], from: localDate)
        guard let year = components.year, let month = components.month, let day = components.day else { return localDate }
        let currentStart = monthStart(forDisplayYear: year, month: month, monthStartDay: monthStartDay, timeZoneIdentifier: timeZoneIdentifier)
        if day >= calendar.component(.day, from: currentStart) { return currentStart }

        let previousDate = calendar.date(byAdding: .month, value: -1, to: makeDate(year: year, month: month, day: 1, calendar: calendar)) ?? localDate
        let previous = calendar.dateComponents([.year, .month], from: previousDate)
        return monthStart(
            forDisplayYear: previous.year ?? year,
            month: previous.month ?? month,
            monthStartDay: monthStartDay,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    static func monthWindow(for date: Date, monthStartDay: Int, timeZoneIdentifier: String) -> FinancialPeriodWindow {
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        let start = financialMonthStart(for: date, monthStartDay: monthStartDay, timeZoneIdentifier: timeZoneIdentifier)
        let components = calendar.dateComponents([.year, .month], from: start)
        let nextDate = calendar.date(byAdding: .month, value: 1, to: makeDate(year: components.year ?? 2000, month: components.month ?? 1, day: 1, calendar: calendar)) ?? start
        let next = calendar.dateComponents([.year, .month], from: nextDate)
        let end = monthStart(
            forDisplayYear: next.year ?? 2000,
            month: next.month ?? 1,
            monthStartDay: monthStartDay,
            timeZoneIdentifier: timeZoneIdentifier
        )
        return FinancialPeriodWindow(start: start, end: end)
    }

    static func shiftedMonth(from date: Date, by offset: Int, monthStartDay: Int, timeZoneIdentifier: String) -> Date {
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        let start = financialMonthStart(for: date, monthStartDay: monthStartDay, timeZoneIdentifier: timeZoneIdentifier)
        let components = calendar.dateComponents([.year, .month], from: start)
        let shiftedDate = calendar.date(byAdding: .month, value: offset, to: makeDate(year: components.year ?? 2000, month: components.month ?? 1, day: 1, calendar: calendar)) ?? start
        let shifted = calendar.dateComponents([.year, .month], from: shiftedDate)
        return monthStart(
            forDisplayYear: shifted.year ?? 2000,
            month: shifted.month ?? 1,
            monthStartDay: monthStartDay,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    static func displayMonthComponents(for date: Date, monthStartDay: Int, timeZoneIdentifier: String) -> DateComponents {
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        return calendar.dateComponents(
            [.year, .month],
            from: financialMonthStart(for: date, monthStartDay: monthStartDay, timeZoneIdentifier: timeZoneIdentifier)
        )
    }

    private static func localDate(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: components) ?? date
    }

    private static func makeDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}

struct AccountMovementCacheKey: Hashable, Sendable {
    let accountID: UUID
    let filter: RemoteMovementFilter
    let typeIsIncome: Bool
    let selectedDayComponents: DateComponents?
    let selectedWeekComponents: DateComponents?
    let selectedMonthComponents: DateComponents?
    let selectedCategoryID: UUID?

    init(
        accountID: UUID,
        filter: RemoteMovementFilter,
        typeIsIncome: Bool,
        selectedDayComponents: DateComponents?,
        selectedWeekComponents: DateComponents?,
        selectedMonthComponents: DateComponents?,
        selectedCategoryID: UUID?
    ) {
        self.accountID = accountID
        self.filter = filter
        self.typeIsIncome = typeIsIncome
        self.selectedDayComponents = selectedDayComponents
        self.selectedWeekComponents = selectedWeekComponents
        self.selectedMonthComponents = selectedMonthComponents
        self.selectedCategoryID = selectedCategoryID
    }
}

struct AccountMovementCacheEntry: Sendable {
    var selectedSnapshot: RemoteAccountSnapshotDTO?
    var summary: RemoteMovementSummaryDTO
    var days: [RemoteMovementDayDTO]
    var upcomingItems: [RemoteUpcomingItemDTO]
    var nextCursor: String?
    var loadedMovementIDs: Set<UUID>
    var lastLoadedAt: Date

    init(
        selectedSnapshot: RemoteAccountSnapshotDTO?,
        summary: RemoteMovementSummaryDTO,
        days: [RemoteMovementDayDTO],
        upcomingItems: [RemoteUpcomingItemDTO],
        nextCursor: String?,
        loadedMovementIDs: Set<UUID>,
        lastLoadedAt: Date = Date()
    ) {
        self.selectedSnapshot = selectedSnapshot
        self.summary = summary
        self.days = days
        self.upcomingItems = upcomingItems
        self.nextCursor = nextCursor
        self.loadedMovementIDs = loadedMovementIDs
        self.lastLoadedAt = lastLoadedAt
    }
}

private struct InFlightMovementRequest {
    let id: Int
    let task: Task<RemoteMovimentiPageDTO, Error>
    var consumers: Int
}

enum RemoteBootstrapStatus: Equatable {
    case idle
    case loading
    case ready
    case failed
}

@MainActor
final class FinancialRemoteStore: ObservableObject {
    static let lastKnownAccountIDDefaultsKey = "remote.lastKnownAccountID"
    private static let movementCacheTTL: TimeInterval = 60
    private static let movementCacheMaximumEntries = 64

    let isRemoteOnly: Bool

    @Published private(set) var profile: RemoteProfileDTO?
    @Published private(set) var accounts: [RemoteAccountDTO] = []
    @Published private(set) var categories: [RemoteCategoryDTO] = []
    @Published private(set) var selectedSnapshot: RemoteAccountSnapshotDTO?
    @Published private(set) var summary = RemoteMovementSummaryDTO(incomeMinor: 0, expensesMinor: 0)
    @Published private(set) var days: [RemoteMovementDayDTO] = []
    @Published private(set) var subscriptions: [RemoteSubscriptionDTO] = []
    @Published private(set) var recurrenceRules: [RemoteRecurrenceRuleDTO] = []
    @Published private(set) var upcomingItems: [RemoteUpcomingItemDTO] = []
    @Published private(set) var budgetSummary: RemoteBudgetSummaryDTO?
    @Published private(set) var isBudgetLoading = false
    @Published private(set) var budgetErrorMessage: String?
    @Published private(set) var nextCursor: String?
    @Published var selectedAccountID: UUID?
    @Published var filter: RemoteMovementFilter = .all
    @Published var typeIsIncome = false
    @Published var selectedDay = Date.now
    @Published var selectedWeek = Date.now
    @Published var selectedMonth = Date.now
    @Published var selectedCategoryID: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingNextPage = false
    @Published var errorMessage: String?
    @Published var deferredFeatureMessage: String?
    @Published private(set) var subscriptionErrorMessage: String?
    @Published private(set) var bootstrapStatus: RemoteBootstrapStatus = .idle
    @Published private(set) var isUpdatingDefaultCurrency = false
    @Published private(set) var isUpdatingFinancialCalendar = false

    var accountCache: [AccountMovementCacheKey: AccountMovementCacheEntry] = [:]

    private let bootstrapRepository: RemoteBootstrapRepository?
    private let accountsRepository: RemoteAccountsRepository?
    private let categoriesRepository: RemoteCategoriesRepository?
    private let movementsRepository: RemoteMovimentiPageProviding?
    private let transactionsRepository: RemoteTransactionsRepository?
    private let subscriptionsRepository: RemoteSubscriptionsRepository?
    private let recurrencesRepository: RemoteRecurrencesRepository?
    private let upcomingRepository: RemoteUpcomingRepository?
    private let budgetRepository: RemoteBudgetRepository?
    private var didBootstrap = false
    private var bootstrapTask: Task<Bool, Never>?
    private var secondaryBootstrapTask: Task<Void, Never>?
    private var movementTask: Task<Void, Never>?
    private var movementTaskAccountID: UUID?
    private var movementTaskIsSpeculative = false
    private var hasAuthoritativeAccountSet = false
    private var hasSelectedWeekPeriod = false
    private var hasSelectedMonthPeriod = false
    private var pendingSpeculativePage: RemoteMovimentiPageDTO?
    private var pendingSpeculativePageGeneration: Int?
    private var pendingSpeculativeUpcoming: RemoteUpcomingResponseDTO?
    private var pendingSpeculativeUpcomingGeneration: Int?
    private var loadedMovementIDs = Set<UUID>()
    private var loadGeneration = 0
    private var nextMovementRequestID = 0
    private var inFlightMovementRequests: [AccountMovementCacheKey: InFlightMovementRequest] = [:]

    init(
        client: APIClient?,
        movementsRepository: RemoteMovimentiPageProviding? = nil,
        initialAccounts: [RemoteAccountDTO] = [],
        initialProfile: RemoteProfileDTO? = nil
    ) {
        isRemoteOnly = client != nil
        if let client {
            bootstrapRepository = RemoteBootstrapRepository(client: client)
            accountsRepository = RemoteAccountsRepository(client: client)
            categoriesRepository = RemoteCategoriesRepository(client: client)
            self.movementsRepository = movementsRepository ?? RemoteMovimentiRepository(client: client)
            transactionsRepository = RemoteTransactionsRepository(client: client)
            subscriptionsRepository = RemoteSubscriptionsRepository(client: client)
            recurrencesRepository = RemoteRecurrencesRepository(client: client)
            upcomingRepository = RemoteUpcomingRepository(client: client)
            budgetRepository = RemoteBudgetRepository(client: client)
        } else {
            bootstrapRepository = nil
            accountsRepository = nil
            categoriesRepository = nil
            self.movementsRepository = movementsRepository
            transactionsRepository = nil
            subscriptionsRepository = nil
            recurrencesRepository = nil
            upcomingRepository = nil
            budgetRepository = nil
        }
        selectedAccountID = Self.loadLastKnownAccountID()
        accounts = initialAccounts
        profile = initialProfile
        hasAuthoritativeAccountSet = !initialAccounts.isEmpty
    }

    var activeAccounts: [RemoteAccountDTO] {
        accounts.filter { !$0.isArchived }.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var selectedAccount: RemoteAccountDTO? {
        guard let selectedAccountID else { return activeAccounts.first }
        return activeAccounts.first(where: { $0.id == selectedAccountID }) ?? activeAccounts.first
    }

    var selectedCurrencyCode: String { selectedSnapshot?.currencyCode ?? selectedAccount?.currencyCode ?? profile?.defaultCurrencyCode ?? "EUR" }
    var selectedCurrencyExponent: Int { selectedSnapshot?.currencyExponent ?? selectedAccount?.currencyExponent ?? 2 }

    @discardableResult
    func bootstrapIfNeeded() async -> Bool {
        guard isRemoteOnly else {
            bootstrapStatus = .failed
            return false
        }
        guard !didBootstrap else { return bootstrapStatus == .ready }
        if let bootstrapTask {
            return await bootstrapTask.value
        }

        let task: Task<Bool, Never> = Task { [weak self] in
            guard let self else { return false }
            return await self.bootstrap()
        }
        bootstrapTask = task
        let result = await task.value
        bootstrapTask = nil
        return result
    }

    @discardableResult
    func bootstrap() async -> Bool {
        guard let bootstrapRepository else {
            bootstrapStatus = .failed
            return false
        }
        movementTask?.cancel()
        cancelInFlightMovementRequests()
        movementTask = nil
        movementTaskAccountID = nil
        movementTaskIsSpeculative = false
        hasAuthoritativeAccountSet = false
        pendingSpeculativePage = nil
        pendingSpeculativePageGeneration = nil
        pendingSpeculativeUpcoming = nil
        pendingSpeculativeUpcomingGeneration = nil
        secondaryBootstrapTask?.cancel()
        secondaryBootstrapTask = nil
        loadGeneration += 1
        let startupGeneration = loadGeneration
        let lastKnownAccountID = selectedAccountID
        bootstrapStatus = .loading
        isLoading = true
        errorMessage = nil
        selectedSnapshot = nil
        clearMovementPageOnly()

        if let lastKnownAccountID, !hasFreshMovementCache(for: lastKnownAccountID) {
            startFirstPageLoad(accountID: lastKnownAccountID, generation: startupGeneration, isSpeculative: true)
        }

        async let bootstrapResponse = bootstrapRepository.load()
        do {
            let response = try await bootstrapResponse
            try Task.checkCancellation()
            profile = response.profile
            accounts = response.accounts
            categories = response.categories
            hasAuthoritativeAccountSet = true
            normalizeSelectedAccount()
            if let selectedAccountID {
                await resolveInitialMovementPage(accountID: selectedAccountID)
            } else {
                pendingSpeculativePage = nil
                pendingSpeculativePageGeneration = nil
                pendingSpeculativeUpcoming = nil
                pendingSpeculativeUpcomingGeneration = nil
                clearMovements()
            }

            guard errorMessage == nil else {
                bootstrapStatus = .failed
                isLoading = false
                return false
            }

            didBootstrap = true
            bootstrapStatus = .ready
            isLoading = false
            startSecondaryBootstrap()
            return true
        } catch is CancellationError {
            movementTask?.cancel()
            movementTask = nil
            movementTaskAccountID = nil
            movementTaskIsSpeculative = false
            pendingSpeculativePage = nil
            pendingSpeculativePageGeneration = nil
            pendingSpeculativeUpcoming = nil
            pendingSpeculativeUpcomingGeneration = nil
            bootstrapStatus = .idle
            isLoading = false
            return false
        } catch {
            movementTask?.cancel()
            movementTask = nil
            movementTaskAccountID = nil
            movementTaskIsSpeculative = false
            pendingSpeculativePage = nil
            pendingSpeculativePageGeneration = nil
            pendingSpeculativeUpcoming = nil
            pendingSpeculativeUpcomingGeneration = nil
            errorMessage = userFacingMessage(for: error)
            bootstrapStatus = .failed
            isLoading = false
            return false
        }
    }

    func loadBudget() async {
        guard let budgetRepository else { return }
        isBudgetLoading = true
        budgetErrorMessage = nil
        do {
            budgetSummary = try await budgetRepository.get()
        } catch is CancellationError {
        } catch {
            budgetErrorMessage = userFacingMessage(for: error)
        }
        isBudgetLoading = false
    }

    func updateDefaultCurrency(_ currencyCode: String) async throws {
        guard !isUpdatingDefaultCurrency, let bootstrapRepository else { return }
        isUpdatingDefaultCurrency = true
        defer { isUpdatingDefaultCurrency = false }

        let profile = try await bootstrapRepository.updateProfile(
            RemoteProfileUpdatePayload(defaultCurrencyCode: currencyCode)
        )
        self.profile = profile
    }

    func updateFinancialCalendar(monthStartDay: Int? = nil, weekStartDay: Int? = nil) async throws {
        guard !isUpdatingFinancialCalendar, let bootstrapRepository else { return }
        isUpdatingFinancialCalendar = true
        defer { isUpdatingFinancialCalendar = false }

        let profile = try await bootstrapRepository.updateProfile(
            RemoteProfileUpdatePayload(monthStartDay: monthStartDay, weekStartDay: weekStartDay)
        )
        self.profile = profile
        invalidateAccountCache()
        await refresh()
    }

    func saveMainBudget(_ payload: RemoteBudgetMutationPayload) async throws {
        guard let budgetRepository else { return }
        budgetSummary = try await budgetRepository.upsertMain(payload)
    }

    func saveCategoryBudget(categoryID: UUID, payload: RemoteBudgetMutationPayload) async throws {
        guard let budgetRepository else { return }
        budgetSummary = try await budgetRepository.upsertCategory(categoryID: categoryID, payload)
    }

    func deleteMainBudget() async throws {
        guard let budgetRepository else { return }
        budgetSummary = try await budgetRepository.deleteMain()
    }

    func deleteCategoryBudget(categoryID: UUID) async throws {
        guard let budgetRepository else { return }
        budgetSummary = try await budgetRepository.deleteCategory(categoryID: categoryID)
    }

    func selectAccount(_ accountID: UUID) {
        guard activeAccounts.contains(where: { $0.id == accountID }) else { return }
        guard selectedAccountID != accountID || selectedSnapshot == nil else { return }
        selectedAccountID = accountID
        persistLastKnownAccountID(accountID)
        resetAndReload(clearOnCacheMiss: true)
    }

    func invalidateAccountCache(for accountID: UUID? = nil) {
        if let accountID {
            invalidateAccountCaches(for: Set([accountID]))
        } else {
            accountCache.removeAll()
            cancelInFlightMovementRequests()
        }
    }

    private func invalidateAccountCaches(for accountIDs: Set<UUID>) {
        guard !accountIDs.isEmpty else { return }
        accountCache = accountCache.filter { !accountIDs.contains($0.key.accountID) }
        cancelInFlightMovementRequests(for: accountIDs)
    }

    private func invalidateMovementCaches(for movementID: UUID, additionalAccountIDs: Set<UUID> = []) {
        let cachedAccountIDs = accountCache.compactMap { key, entry in
            entry.loadedMovementIDs.contains(movementID) ? key.accountID : nil
        }
        invalidateAccountCaches(for: Set(cachedAccountIDs).union(additionalAccountIDs))
    }

    func cacheKey(for accountID: UUID) -> AccountMovementCacheKey {
        let timeZoneIdentifier = profile?.timezone ?? FinancialPeriodNavigator.fallbackTimeZone
        let weekStartDay = profile?.weekStartDay ?? 1
        let monthStartDay = profile?.monthStartDay ?? 1
        return AccountMovementCacheKey(
            accountID: accountID,
            filter: filter,
            typeIsIncome: typeIsIncome,
            selectedDayComponents: filter == .day ? Calendar.current.dateComponents([.year, .month, .day], from: selectedDay) : nil,
            selectedWeekComponents: filter == .week ? Calendar.current.dateComponents([.year, .month, .day], from: FinancialPeriodNavigator.weekStart(for: selectedWeek, weekStartDay: weekStartDay, timeZoneIdentifier: timeZoneIdentifier)) : nil,
            selectedMonthComponents: filter == .month ? FinancialPeriodNavigator.displayMonthComponents(for: selectedMonth, monthStartDay: monthStartDay, timeZoneIdentifier: timeZoneIdentifier) : nil,
            selectedCategoryID: filter == .category ? selectedCategoryID : nil
        )
    }

    func cachedSnapshot(for accountID: UUID) -> RemoteAccountSnapshotDTO? {
        if selectedAccountID == accountID, let selectedSnapshot {
            return selectedSnapshot
        }
        let key = cacheKey(for: accountID)
        return accountCache[key]?.selectedSnapshot
    }

    func cachedSummary(for accountID: UUID) -> RemoteMovementSummaryDTO? {
        if selectedAccountID == accountID {
            return summary
        }
        let key = cacheKey(for: accountID)
        return accountCache[key]?.summary
    }

    func cachedDays(for accountID: UUID) -> [RemoteMovementDayDTO] {
        if selectedAccountID == accountID {
            return days
        }
        let key = cacheKey(for: accountID)
        return accountCache[key]?.days ?? []
    }

    func refresh() async {
        guard let selectedAccountID else { return }
        isRefreshing = true
        invalidateAccountCache(for: selectedAccountID)
        if filter != .upcoming { _ = try? await recurrencesRepository?.materialize() }
        await fetchFirstPage(accountID: selectedAccountID)
        isRefreshing = false
    }

    func loadNextPageIfNeeded(after movementID: UUID) {
        guard let lastMovementID = days.last?.movements.last?.id,
              movementID == lastMovementID,
              nextCursor != nil,
              !isLoadingNextPage,
              filter != .upcoming,
              let selectedAccountID else { return }
        isLoadingNextPage = true
        let cursor = nextCursor
        let generation = loadGeneration
        movementTask?.cancel()
        movementTaskAccountID = selectedAccountID
        movementTask = Task { [weak self] in
            guard let self, let movementsRepository = self.movementsRepository else { return }
            do {
                let page = try await movementsRepository.page(
                    accountID: selectedAccountID,
                    limit: 50,
                    cursor: cursor,
                    filter: self.filter.rawValue,
                    income: self.filter == .type ? self.typeIsIncome : nil,
                    day: self.filter == .day ? self.remoteDateOnly(self.selectedDay) : nil,
                    weekStart: self.filter == .week ? self.remoteFinancialDateOnly(self.canonicalWeekStart(self.selectedWeek)) : nil,
                    month: self.filter == .month ? self.remoteFinancialMonth(self.canonicalMonthStart(self.selectedMonth)) : nil,
                    categoryID: self.filter == .category ? self.selectedCategoryID : nil
                )
                try Task.checkCancellation()
                guard generation == self.loadGeneration, self.selectedAccountID == selectedAccountID else { return }
                self.append(page)
            } catch is CancellationError {
            } catch {
                self.errorMessage = self.userFacingMessage(for: error)
            }
            self.isLoadingNextPage = false
        }
    }

    func setFilter(_ newFilter: RemoteMovementFilter) {
        let previousKey = selectedAccountID.map { cacheKey(for: $0) }
        if newFilter == .all {
            typeIsIncome = false
            selectedDay = .now
            selectedWeek = .now
            selectedMonth = .now
            selectedCategoryID = nil
            hasSelectedWeekPeriod = false
            hasSelectedMonthPeriod = false
        } else if newFilter == .week && filter != .week && !hasSelectedWeekPeriod {
            selectedWeek = FinancialPeriodNavigator.weekStart(
                for: .now,
                weekStartDay: profile?.weekStartDay ?? 1,
                timeZoneIdentifier: profile?.timezone ?? FinancialPeriodNavigator.fallbackTimeZone
            )
            hasSelectedWeekPeriod = true
        } else if newFilter == .month && filter != .month && !hasSelectedMonthPeriod {
            selectedMonth = FinancialPeriodNavigator.financialMonthStart(
                for: .now,
                monthStartDay: profile?.monthStartDay ?? 1,
                timeZoneIdentifier: profile?.timezone ?? FinancialPeriodNavigator.fallbackTimeZone
            )
            hasSelectedMonthPeriod = true
        }
        filter = newFilter
        guard selectedAccountID.map({ cacheKey(for: $0) }) != previousKey else { return }
        resetAndReload()
    }

    func moveWeek(by offset: Int) {
        let previousKey = selectedAccountID.map { cacheKey(for: $0) }
        selectedWeek = FinancialPeriodNavigator.shiftedWeek(
            from: hasSelectedWeekPeriod ? selectedWeek : .now,
            by: offset,
            weekStartDay: profile?.weekStartDay ?? 1,
            timeZoneIdentifier: profile?.timezone ?? FinancialPeriodNavigator.fallbackTimeZone
        )
        hasSelectedWeekPeriod = true
        filter = .week
        guard selectedAccountID.map({ cacheKey(for: $0) }) != previousKey else { return }
        resetAndReload()
    }

    func moveMonth(by offset: Int) {
        let previousKey = selectedAccountID.map { cacheKey(for: $0) }
        selectedMonth = FinancialPeriodNavigator.shiftedMonth(
            from: hasSelectedMonthPeriod ? selectedMonth : .now,
            by: offset,
            monthStartDay: profile?.monthStartDay ?? 1,
            timeZoneIdentifier: profile?.timezone ?? FinancialPeriodNavigator.fallbackTimeZone
        )
        hasSelectedMonthPeriod = true
        filter = .month
        guard selectedAccountID.map({ cacheKey(for: $0) }) != previousKey else { return }
        resetAndReload()
    }

    func selectMonth(_ date: Date) {
        let targetMonth = FinancialPeriodNavigator.financialMonthStart(
            for: date,
            monthStartDay: profile?.monthStartDay ?? 1,
            timeZoneIdentifier: profile?.timezone ?? FinancialPeriodNavigator.fallbackTimeZone
        )
        let calendar = FinancialPeriodNavigator.calendar(timeZoneIdentifier: profile?.timezone ?? FinancialPeriodNavigator.fallbackTimeZone)
        let currentComponents = calendar.dateComponents([.year, .month, .day], from: canonicalMonthStart(selectedMonth))
        let targetComponents = calendar.dateComponents([.year, .month, .day], from: targetMonth)
        guard filter != .month || currentComponents != targetComponents else { return }
        selectedMonth = targetMonth
        hasSelectedMonthPeriod = true
        filter = .month
        resetAndReload()
    }

    func setCategoryFilter(_ categoryID: UUID?) {
        guard filter != .category || selectedCategoryID != categoryID else { return }
        let previousKey = selectedAccountID.map { cacheKey(for: $0) }
        selectedCategoryID = categoryID
        filter = .category
        guard selectedAccountID.map({ cacheKey(for: $0) }) != previousKey else { return }
        resetAndReload()
    }

    func setTypeFilter(previousValue: Bool) {
        let filterChanged = filter != .type
        let typeChanged = previousValue != typeIsIncome
        filter = .type
        guard filterChanged || typeChanged else { return }
        resetAndReload()
    }

    func awaitCurrentMovementLoad() async {
        await movementTask?.value
    }

    func moveWeekAndWait(by offset: Int) async {
        moveWeek(by: offset)
        await movementTask?.value
    }

    func moveMonthAndWait(by offset: Int) async {
        moveMonth(by: offset)
        await movementTask?.value
    }

    func selectMonthAndWait(_ date: Date) async {
        selectMonth(date)
        await movementTask?.value
    }

    func setDayFilterAndWait(previousDay: Date) async {
        setDayFilter(previousDay: previousDay)
        await movementTask?.value
    }

    func setDayFilter(previousDay: Date) {
        let calendar = Calendar.current
        guard filter != .day || !calendar.isDate(previousDay, inSameDayAs: selectedDay) else { return }
        filter = .day
        resetAndReload()
    }

    func createAccount(_ payload: RemoteAccountCreatePayload) async throws {
        guard let accountsRepository else { return }
        let account = try await accountsRepository.create(payload)
        accounts.append(account)
        normalizeSelectedAccount()
        if selectedSnapshot == nil, let selectedAccountID { await fetchFirstPage(accountID: selectedAccountID) }
    }

    func updateAccount(_ accountID: UUID, payload: RemoteAccountUpdatePayload) async throws {
        guard let accountsRepository else { return }
        let updated = try await accountsRepository.update(accountID: accountID, payload)
        replaceAccount(updated)
        normalizeSelectedAccount()
    }

    func archiveAccount(_ accountID: UUID) async throws {
        guard let accountsRepository else { return }
        let archived = try await accountsRepository.archive(accountID: accountID)
        replaceAccount(archived)
        normalizeSelectedAccount()
        if let selectedAccountID { await fetchFirstPage(accountID: selectedAccountID) } else { clearMovements() }
    }

    @discardableResult
    func createCategory(_ payload: RemoteCategoryCreatePayload) async throws -> RemoteCategoryDTO {
        guard let categoriesRepository else { throw APIError.unauthorized(nil) }
        let created = try await categoriesRepository.create(payload)
        categories.append(created)
        categories.sort {
            if $0.income != $1.income { return !$0.income }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return created
    }

    @discardableResult
    func activateCategoryPreset(_ preset: CategoryPreset) async throws -> RemoteCategoryDTO {
        guard let categoriesRepository else { throw APIError.unauthorized(nil) }
        let activated = try await categoriesRepository.activatePreset(
            key: preset.key,
            income: preset.income,
            displayName: preset.localizedTitle
        )
        if let index = categories.firstIndex(where: { $0.id == activated.id }) {
            categories[index] = activated
        } else {
            categories.append(activated)
        }
        categories.sort {
            if $0.income != $1.income { return !$0.income }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return activated
    }

    func updateCategory(_ categoryID: UUID, payload: RemoteCategoryUpdatePayload) async throws {
        guard let categoriesRepository else { return }
        let updated = try await categoriesRepository.update(categoryID: categoryID, payload)
        if let index = categories.firstIndex(where: { $0.id == categoryID }) { categories[index] = updated }
    }

    func deleteCategory(_ categoryID: UUID) async throws {
        guard let categoriesRepository else { return }
        let deleted = try await categoriesRepository.delete(categoryID: categoryID)
        categories.removeAll { $0.id == deleted.id }
        if selectedCategoryID == categoryID { selectedCategoryID = nil }
    }

    @discardableResult
    func createTransaction(_ payload: RemoteTransactionCreatePayload) async throws -> RemoteTransactionDTO? {
        guard let transactionsRepository else { return nil }
        let result = try await transactionsRepository.create(payload)
        invalidateAccountCache(for: payload.accountID)
        await refresh()
        return result
    }

    @discardableResult
    func createRecurrence(_ payload: RemoteRecurrenceCreatePayload) async throws -> RemoteRecurrenceRuleDTO? {
        guard let recurrencesRepository else { return nil }
        let result = try await recurrencesRepository.create(payload)
        invalidateAccountCache(for: payload.accountID)
        _ = try await recurrencesRepository.materialize()
        recurrenceRules = try await recurrencesRepository.list()
        await refresh()
        return result
    }

    @discardableResult
    func updateRecurrence(_ ruleID: UUID, payload: RemoteRecurrenceUpdatePayload) async throws -> RemoteRecurrenceRuleDTO? {
        guard let recurrencesRepository else { return nil }
        let existingAccountID = recurrenceRules.first(where: { $0.id == ruleID })?.accountID
        let result = try await recurrencesRepository.update(ruleID: ruleID, payload)
        invalidateAccountCaches(for: Set([existingAccountID, payload.accountID].compactMap { $0 }))
        _ = try await recurrencesRepository.materialize()
        recurrenceRules = try await recurrencesRepository.list()
        await refresh()
        return result
    }

    func pauseRecurrence(_ ruleID: UUID) async throws {
        guard let recurrencesRepository else { return }
        let accountID = recurrenceRules.first(where: { $0.id == ruleID })?.accountID
        _ = try await recurrencesRepository.pause(ruleID: ruleID)
        if let accountID { invalidateAccountCache(for: accountID) }
        recurrenceRules = try await recurrencesRepository.list()
    }

    func resumeRecurrence(_ ruleID: UUID) async throws {
        guard let recurrencesRepository else { return }
        let accountID = recurrenceRules.first(where: { $0.id == ruleID })?.accountID
        _ = try await recurrencesRepository.resume(ruleID: ruleID)
        if let accountID { invalidateAccountCache(for: accountID) }
        _ = try await recurrencesRepository.materialize()
        recurrenceRules = try await recurrencesRepository.list()
        await refresh()
    }

    func cancelRecurrence(_ ruleID: UUID) async throws {
        guard let recurrencesRepository else { return }
        let accountID = recurrenceRules.first(where: { $0.id == ruleID })?.accountID
        _ = try await recurrencesRepository.cancel(ruleID: ruleID)
        if let accountID { invalidateAccountCache(for: accountID) }
        recurrenceRules = try await recurrencesRepository.list()
        await refresh()
    }

    @discardableResult
    func updateTransaction(_ transactionID: UUID, payload: RemoteTransactionUpdatePayload) async throws -> RemoteTransactionDTO? {
        guard let transactionsRepository else { return nil }
        let result = try await transactionsRepository.update(transactionID: transactionID, payload)
        invalidateMovementCaches(for: transactionID, additionalAccountIDs: Set([payload.accountID].compactMap { $0 }))
        await refresh()
        return result
    }

    func deleteTransaction(_ transactionID: UUID) async throws {
        guard let transactionsRepository else { return }
        try await transactionsRepository.delete(transactionID: transactionID)
        invalidateMovementCaches(for: transactionID)
        await refresh()
    }

    @discardableResult
    func createTransfer(_ payload: RemoteTransferCreatePayload) async throws -> RemoteTransactionDTO? {
        guard let transactionsRepository else { return nil }
        let result = try await transactionsRepository.createTransfer(payload)
        invalidateAccountCaches(for: Set([payload.sourceAccountID, payload.destinationAccountID]))
        await refresh()
        return result
    }

    func loadSubscriptions() async throws {
        guard let subscriptionsRepository else { return }
        subscriptionErrorMessage = nil
        do {
            _ = try await subscriptionsRepository.materialize()
            subscriptions = try await subscriptionsRepository.list()
            invalidateAccountCaches(for: Set(subscriptions.map(\.accountID)))
        } catch {
            subscriptionErrorMessage = userFacingMessage(for: error)
            throw error
        }
    }

    @discardableResult
    func createSubscription(_ payload: RemoteSubscriptionCreatePayload) async throws -> RemoteSubscriptionDTO? {
        guard let subscriptionsRepository else { return nil }
        let result = try await subscriptionsRepository.create(payload)
        invalidateAccountCache(for: payload.accountID)
        _ = try await subscriptionsRepository.materialize()
        subscriptions = try await subscriptionsRepository.list()
        await refresh()
        return result
    }

    @discardableResult
    func updateSubscription(_ subscriptionID: UUID, payload: RemoteSubscriptionUpdatePayload) async throws -> RemoteSubscriptionDTO? {
        guard let subscriptionsRepository else { return nil }
        let existingAccountID = subscriptions.first(where: { $0.id == subscriptionID })?.accountID
        let result = try await subscriptionsRepository.update(subscriptionID: subscriptionID, payload)
        invalidateAccountCaches(for: Set([existingAccountID, payload.accountID].compactMap { $0 }))
        _ = try await subscriptionsRepository.materialize()
        subscriptions = try await subscriptionsRepository.list()
        await refresh()
        return result
    }

    func pauseSubscription(_ subscriptionID: UUID) async throws {
        guard let subscriptionsRepository else { return }
        let accountID = subscriptions.first(where: { $0.id == subscriptionID })?.accountID
        _ = try await subscriptionsRepository.pause(subscriptionID: subscriptionID)
        if let accountID { invalidateAccountCache(for: accountID) }
        subscriptions = try await subscriptionsRepository.list()
    }

    func resumeSubscription(_ subscriptionID: UUID) async throws {
        guard let subscriptionsRepository else { return }
        let accountID = subscriptions.first(where: { $0.id == subscriptionID })?.accountID
        _ = try await subscriptionsRepository.resume(subscriptionID: subscriptionID)
        if let accountID { invalidateAccountCache(for: accountID) }
        subscriptions = try await subscriptionsRepository.list()
    }

    func cancelSubscription(_ subscriptionID: UUID) async throws {
        guard let subscriptionsRepository else { return }
        let accountID = subscriptions.first(where: { $0.id == subscriptionID })?.accountID
        _ = try await subscriptionsRepository.cancel(subscriptionID: subscriptionID)
        if let accountID { invalidateAccountCache(for: accountID) }
        subscriptions = try await subscriptionsRepository.list()
    }

    func resetRemoteState() {
        movementTask?.cancel()
        cancelInFlightMovementRequests()
        movementTask = nil
        movementTaskAccountID = nil
        movementTaskIsSpeculative = false
        pendingSpeculativePage = nil
        pendingSpeculativePageGeneration = nil
        pendingSpeculativeUpcoming = nil
        pendingSpeculativeUpcomingGeneration = nil
        bootstrapTask?.cancel()
        bootstrapTask = nil
        secondaryBootstrapTask?.cancel()
        secondaryBootstrapTask = nil
        didBootstrap = false
        bootstrapStatus = .idle
        profile = nil
        accounts = []
        categories = []
        subscriptions = []
        recurrenceRules = []
        upcomingItems = []
        budgetSummary = nil
        budgetErrorMessage = nil
        selectedAccountID = nil
        clearLastKnownAccountID()
        selectedSnapshot = nil
        clearMovements()
        accountCache.removeAll()
        subscriptionErrorMessage = nil
        errorMessage = nil
    }

    private func startSecondaryBootstrap() {
        secondaryBootstrapTask?.cancel()
        secondaryBootstrapTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.recurrencesRepository?.materialize()
                self.recurrenceRules = try await self.recurrencesRepository?.list() ?? []
                _ = try await self.subscriptionsRepository?.materialize()
                self.subscriptions = try await self.subscriptionsRepository?.list() ?? []
            } catch is CancellationError {
            } catch {
                // Secondary tab data must not prevent the essential Movimenti UI from opening.
            }
        }
    }

    private func resolveInitialMovementPage(accountID: UUID) async {
        guard selectedAccountID == accountID else { return }

        if let pendingPage = pendingSpeculativePage,
           pendingSpeculativePageGeneration == loadGeneration,
           pendingPage.account.id == accountID {
            pendingSpeculativePage = nil
            pendingSpeculativePageGeneration = nil
            publish(pendingPage, for: accountID, key: cacheKey(for: accountID))
            return
        }
        if filter == .upcoming,
           let pendingUpcoming = pendingSpeculativeUpcoming,
           pendingSpeculativeUpcomingGeneration == loadGeneration,
           pendingUpcoming.account.id == accountID {
            pendingSpeculativeUpcoming = nil
            pendingSpeculativeUpcomingGeneration = nil
            publish(pendingUpcoming, for: accountID)
            return
        }

        let decision = RemoteStartupFastPathDecision.resolve(
            lastKnownAccountID: selectedAccountID,
            authoritativeAccountID: accountID,
            speculativePageAccountID: movementTaskAccountID,
            hasFreshCache: hasFreshMovementCache(for: accountID),
            hasInFlightPage: movementTask != nil
        )
        switch decision {
        case .useFreshCache:
            if let cached = freshMovementCache(for: accountID) {
                publish(cached, for: accountID, key: cacheKey(for: accountID))
            }
            return
        case .awaitSpeculativePage:
            guard let movementTask else { return }
            await movementTask.value
        case .fetchAuthoritativePage:
            startFirstPageLoad(accountID: accountID, generation: loadGeneration)
            await movementTask?.value
        }

        guard selectedAccountID == accountID else { return }
        guard selectedSnapshot?.id != accountID else { return }

        // A speculative request is optional. If it failed, retry through the
        // normal authoritative path before bootstrap completes.
        errorMessage = nil
        startFirstPageLoad(accountID: accountID, generation: loadGeneration)
        await movementTask?.value
    }

    private func startFirstPageLoad(
        accountID: UUID,
        generation: Int,
        isSpeculative: Bool = false,
        clearOnCacheMiss: Bool = false
    ) {
        movementTask?.cancel()
        movementTaskAccountID = accountID
        movementTaskIsSpeculative = isSpeculative
        if !isSpeculative {
            pendingSpeculativePage = nil
            pendingSpeculativePageGeneration = nil
            pendingSpeculativeUpcoming = nil
            pendingSpeculativeUpcomingGeneration = nil
        }

        let key = cacheKey(for: accountID)
        if filter != .upcoming, let cached = accountCache[key] {
            publish(cached, for: accountID, key: key)
            if isFresh(cached) {
                movementTask = nil
                return
            }
        } else if clearOnCacheMiss {
            clearMovements()
        }

        movementTask = Task { [weak self] in
            guard let self else { return }
            await self.fetchFirstPage(accountID: accountID, generation: generation, key: key)
        }
    }

    private func freshMovementCache(for accountID: UUID) -> AccountMovementCacheEntry? {
        let key = cacheKey(for: accountID)
        guard let cached = accountCache[key], isFresh(cached) else { return nil }
        return cached
    }

    private func isFresh(_ entry: AccountMovementCacheEntry) -> Bool {
        Date().timeIntervalSince(entry.lastLoadedAt) < Self.movementCacheTTL
    }

    private func hasFreshMovementCache(for accountID: UUID) -> Bool {
        freshMovementCache(for: accountID) != nil
    }

    private func publish(_ cached: AccountMovementCacheEntry, for accountID: UUID, key: AccountMovementCacheKey) {
        guard cached.selectedSnapshot?.id == accountID, isCurrentSelection(accountID: accountID, key: key) else { return }
        selectedSnapshot = cached.selectedSnapshot
        summary = cached.summary
        days = cached.days
        upcomingItems = cached.upcomingItems
        nextCursor = cached.nextCursor
        loadedMovementIDs = cached.loadedMovementIDs
        errorMessage = nil
    }

    private func publish(_ page: RemoteMovimentiPageDTO, for accountID: UUID, key: AccountMovementCacheKey) {
        let existingUpcomingItems = accountCache[key]?.upcomingItems ?? []
        let pageMovementIDs = Set(page.days.flatMap(\.movements).map(\.id))
        accountCache[key] = AccountMovementCacheEntry(
            selectedSnapshot: page.account,
            summary: page.summary,
            days: page.days,
            upcomingItems: existingUpcomingItems,
            nextCursor: page.nextCursor,
            loadedMovementIDs: pageMovementIDs
        )
        pruneMovementCache()

        guard isCurrentSelection(accountID: accountID, key: key) else { return }
        selectedSnapshot = page.account
        summary = page.summary
        days = page.days
        nextCursor = page.nextCursor
        loadedMovementIDs = pageMovementIDs
        errorMessage = nil
    }

    private func isCurrentSelection(accountID: UUID, key: AccountMovementCacheKey) -> Bool {
        selectedAccountID == accountID && cacheKey(for: accountID) == key
    }

    private func sharedMovementRequest(
        key: AccountMovementCacheKey,
        repository: RemoteMovimentiPageProviding,
        accountID: UUID,
        filter: RemoteMovementFilter,
        typeIsIncome: Bool,
        day: RemoteDateOnly?,
        weekStart: RemoteDateOnly?,
        month: String?,
        categoryID: UUID?
    ) -> InFlightMovementRequest {
        if let existing = inFlightMovementRequests[key] {
            var retained = existing
            retained.consumers += 1
            inFlightMovementRequests[key] = retained
            return existing
        }

        nextMovementRequestID += 1
        let requestID = nextMovementRequestID
        let task = Task {
            try await repository.page(
                accountID: accountID,
                limit: 50,
                cursor: nil,
                filter: filter.rawValue,
                income: filter == .type ? typeIsIncome : nil,
                day: day,
                weekStart: weekStart,
                month: month,
                categoryID: categoryID
            )
        }
        let request = InFlightMovementRequest(id: requestID, task: task, consumers: 1)
        inFlightMovementRequests[key] = request
        return request
    }

    private func removeMovementRequest(_ key: AccountMovementCacheKey, id: Int) {
        guard var request = inFlightMovementRequests[key], request.id == id else { return }
        request.consumers -= 1
        if request.consumers == 0 {
            inFlightMovementRequests[key] = nil
        } else {
            inFlightMovementRequests[key] = request
        }
    }

    private func cancelInFlightMovementRequests(for accountIDs: Set<UUID>? = nil) {
        let keys = inFlightMovementRequests.keys.filter { key in
            accountIDs == nil || accountIDs?.contains(key.accountID) == true
        }
        for key in keys {
            inFlightMovementRequests[key]?.task.cancel()
            inFlightMovementRequests[key] = nil
        }
    }

    private func cache(_ page: RemoteMovimentiPageDTO, key: AccountMovementCacheKey) {
        let existingUpcomingItems = accountCache[key]?.upcomingItems ?? []
        accountCache[key] = AccountMovementCacheEntry(
            selectedSnapshot: page.account,
            summary: page.summary,
            days: page.days,
            upcomingItems: existingUpcomingItems,
            nextCursor: page.nextCursor,
            loadedMovementIDs: Set(page.days.flatMap(\.movements).map(\.id))
        )
        pruneMovementCache()
    }

    private func pruneMovementCache() {
        guard accountCache.count > Self.movementCacheMaximumEntries else { return }
        let keysToRemove = accountCache
            .sorted { $0.value.lastLoadedAt > $1.value.lastLoadedAt }
            .dropFirst(Self.movementCacheMaximumEntries)
            .map(\.key)
        for key in keysToRemove {
            accountCache[key] = nil
        }
    }

    private func publish(_ response: RemoteUpcomingResponseDTO, for accountID: UUID) {
        guard selectedAccountID == accountID else { return }
        upcomingItems = response.items
        clearMovementPageOnly()
        errorMessage = nil

        accountCache[cacheKey(for: accountID)] = AccountMovementCacheEntry(
            selectedSnapshot: selectedSnapshot,
            summary: summary,
            days: days,
            upcomingItems: upcomingItems,
            nextCursor: nextCursor,
            loadedMovementIDs: loadedMovementIDs
        )
        pruneMovementCache()
    }

    private func fetchFirstPage(
        accountID: UUID,
        generation: Int? = nil,
        key: AccountMovementCacheKey? = nil
    ) async {
        let requestFilter = filter
        if requestFilter == .upcoming {
            await fetchUpcoming(accountID: accountID, generation: generation)
            return
        }
        guard let movementsRepository else { return }
        let expectedGeneration = generation ?? loadGeneration
        let requestKey = key ?? cacheKey(for: accountID)
        let requestTypeIsIncome = typeIsIncome
        let requestDay = requestFilter == .day ? remoteDateOnly(selectedDay) : nil
        let requestWeekStart = requestFilter == .week ? remoteFinancialDateOnly(canonicalWeekStart(selectedWeek)) : nil
        let requestMonth = requestFilter == .month ? remoteFinancialMonth(canonicalMonthStart(selectedMonth)) : nil
        let requestCategoryID = requestFilter == .category ? selectedCategoryID : nil

        if requestFilter == .recurring {
            do {
                invalidateAccountCache()
                _ = try await recurrencesRepository?.materialize()
            } catch is CancellationError {
                return
            } catch {
                guard expectedGeneration == loadGeneration else { return }
                errorMessage = userFacingMessage(for: error)
                return
            }
        }

        let request = sharedMovementRequest(
            key: requestKey,
            repository: movementsRepository,
            accountID: accountID,
            filter: requestFilter,
            typeIsIncome: requestTypeIsIncome,
            day: requestDay,
            weekStart: requestWeekStart,
            month: requestMonth,
            categoryID: requestCategoryID
        )

        defer { removeMovementRequest(requestKey, id: request.id) }

        do {
            let page = try await request.task.value
            cache(page, key: requestKey)
            try Task.checkCancellation()
            guard RemoteStartupFastPathDecision.canPublish(
                pageAccountID: page.account.id,
                intendedAccountID: accountID,
                expectedGeneration: expectedGeneration,
                currentGeneration: loadGeneration,
                hasAuthoritativeAccountSet: true
            ), isCurrentSelection(accountID: accountID, key: requestKey) else { return }
            if RemoteStartupFastPathDecision.shouldDeferSpeculativePage(
                isSpeculative: movementTaskIsSpeculative,
                hasAuthoritativeAccountSet: hasAuthoritativeAccountSet
            ) {
                pendingSpeculativePage = page
                pendingSpeculativePageGeneration = expectedGeneration
                return
            }
            publish(page, for: accountID, key: requestKey)
        } catch is CancellationError {
        } catch {
            guard expectedGeneration == loadGeneration else { return }
            errorMessage = userFacingMessage(for: error)
        }
    }

    private func fetchUpcoming(accountID: UUID, generation: Int? = nil) async {
        guard let upcomingRepository else { return }
        let expectedGeneration = generation ?? loadGeneration
        do {
            _ = try await recurrencesRepository?.materialize()
            let response = try await upcomingRepository.list(accountID: accountID, limit: 50)
            try Task.checkCancellation()
            guard RemoteStartupFastPathDecision.canPublish(
                pageAccountID: response.account.id,
                intendedAccountID: accountID,
                expectedGeneration: expectedGeneration,
                currentGeneration: loadGeneration,
                hasAuthoritativeAccountSet: true
            ), selectedAccountID == accountID else { return }
            if RemoteStartupFastPathDecision.shouldDeferSpeculativePage(
                isSpeculative: movementTaskIsSpeculative,
                hasAuthoritativeAccountSet: hasAuthoritativeAccountSet
            ) {
                pendingSpeculativeUpcoming = response
                pendingSpeculativeUpcomingGeneration = expectedGeneration
                return
            }
            publish(response, for: accountID)
        } catch is CancellationError {
        } catch {
            guard expectedGeneration == loadGeneration else { return }
            errorMessage = userFacingMessage(for: error)
        }
    }

    private func append(_ page: RemoteMovimentiPageDTO) {
        selectedSnapshot = page.account
        summary = page.summary
        for day in page.days {
            let uniqueMovements = day.movements.filter { loadedMovementIDs.insert($0.id).inserted }
            guard !uniqueMovements.isEmpty else { continue }
            if let index = days.firstIndex(where: { $0.day == day.day }) {
                let merged = days[index].movements + uniqueMovements
                days[index] = RemoteMovementDayDTO(day: day.day, subtotalMinor: days[index].subtotalMinor, movements: merged)
            } else {
                days.append(RemoteMovementDayDTO(day: day.day, subtotalMinor: day.subtotalMinor, movements: uniqueMovements))
            }
        }
        days.sort { $0.day > $1.day }
        nextCursor = page.nextCursor

        if let selectedAccountID {
            let key = cacheKey(for: selectedAccountID)
            accountCache[key] = AccountMovementCacheEntry(
                selectedSnapshot: selectedSnapshot,
                summary: summary,
                days: days,
                upcomingItems: upcomingItems,
                nextCursor: nextCursor,
                loadedMovementIDs: loadedMovementIDs
            )
            pruneMovementCache()
        }
    }

    private func resetAndReload(clearOnCacheMiss: Bool = false) {
        loadGeneration += 1
        movementTask?.cancel()
        movementTask = nil
        movementTaskAccountID = nil
        movementTaskIsSpeculative = false
        pendingSpeculativePage = nil
        pendingSpeculativePageGeneration = nil
        pendingSpeculativeUpcoming = nil
        pendingSpeculativeUpcomingGeneration = nil
        guard let selectedAccountID else { clearMovements(); return }
        let generation = loadGeneration
        startFirstPageLoad(
            accountID: selectedAccountID,
            generation: generation,
            clearOnCacheMiss: clearOnCacheMiss
        )
    }

    private func normalizeSelectedAccount() {
        let valid = selectedAccountID.flatMap { id in activeAccounts.contains(where: { $0.id == id }) ? id : nil }
        let normalized = valid ?? activeAccounts.first?.id
        if selectedAccountID != normalized {
            selectedAccountID = normalized
            loadGeneration += 1
        }
        if let normalized {
            persistLastKnownAccountID(normalized)
        } else {
            clearLastKnownAccountID()
        }
    }

    private static func loadLastKnownAccountID() -> UUID? {
        let defaults = UserDefaults(suiteName: "group.com.saied.sa7tot") ?? .standard
        guard let rawValue = defaults.string(forKey: lastKnownAccountIDDefaultsKey) else { return nil }
        return UUID(uuidString: rawValue)
    }

    private func persistLastKnownAccountID(_ accountID: UUID) {
        let defaults = UserDefaults(suiteName: "group.com.saied.sa7tot") ?? .standard
        defaults.set(accountID.uuidString, forKey: Self.lastKnownAccountIDDefaultsKey)
    }

    private func clearLastKnownAccountID() {
        let defaults = UserDefaults(suiteName: "group.com.saied.sa7tot") ?? .standard
        defaults.removeObject(forKey: Self.lastKnownAccountIDDefaultsKey)
    }

    private func replaceAccount(_ account: RemoteAccountDTO) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index] = account }
        else { accounts.append(account) }
    }

    private func clearMovements() {
        clearMovementPageOnly()
        upcomingItems = []
    }

    private func clearMovementPageOnly() {
        selectedSnapshot = nil
        summary = RemoteMovementSummaryDTO(incomeMinor: 0, expensesMinor: 0)
        days = []
        nextCursor = nil
        loadedMovementIDs.removeAll()
    }

    private func remoteDateOnly(_ date: Date) -> RemoteDateOnly? {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return try? RemoteDateOnly(year: year, month: month, day: day)
    }

    private func remoteFinancialDateOnly(_ date: Date) -> RemoteDateOnly? {
        let calendar = FinancialPeriodNavigator.calendar(timeZoneIdentifier: profile?.timezone ?? FinancialPeriodNavigator.fallbackTimeZone)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return try? RemoteDateOnly(year: year, month: month, day: day)
    }

    private func remoteFinancialMonth(_ date: Date) -> String {
        let calendar = FinancialPeriodNavigator.calendar(timeZoneIdentifier: profile?.timezone ?? FinancialPeriodNavigator.fallbackTimeZone)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 2000,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private func canonicalWeekStart(_ date: Date) -> Date {
        FinancialPeriodNavigator.weekStart(
            for: date,
            weekStartDay: profile?.weekStartDay ?? 1,
            timeZoneIdentifier: profile?.timezone ?? FinancialPeriodNavigator.fallbackTimeZone
        )
    }

    private func canonicalMonthStart(_ date: Date) -> Date {
        FinancialPeriodNavigator.financialMonthStart(
            for: date,
            monthStartDay: profile?.monthStartDay ?? 1,
            timeZoneIdentifier: profile?.timezone ?? FinancialPeriodNavigator.fallbackTimeZone
        )
    }

    private func remoteMonth(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 2000,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    func userFacingMessage(for error: Error) -> String {
        if let error = error as? APIError {
            switch error {
            case .unauthorized: return AppLocalization.string("error.unauthorized")
            case .forbidden: return AppLocalization.string("error.forbidden")
            case .notFound: return AppLocalization.string("error.notFound")
            case .validation: return AppLocalization.string("error.validation")
            case .server: return AppLocalization.string("error.server")
            case .transport: return AppLocalization.string("error.network")
            default: return AppLocalization.string("error.generic")
            }
        }
        return AppLocalization.string("error.generic")
    }
}
