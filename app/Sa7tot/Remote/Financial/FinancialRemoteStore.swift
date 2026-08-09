import Combine
import Foundation

enum RemoteMovementFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case type
    case day
    case week
    case month
    case category
    case recurring
    case upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Tutti i movimenti"
        case .type: return "Per tipo"
        case .day: return "Per giorno"
        case .week: return "Per settimana"
        case .month: return "Per mese"
        case .category: return "Per categoria"
        case .recurring: return "Ricorrenti"
        case .upcoming: return "In arrivo"
        }
    }
}

@MainActor
final class FinancialRemoteStore: ObservableObject {
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

    private let bootstrapRepository: RemoteBootstrapRepository?
    private let accountsRepository: RemoteAccountsRepository?
    private let categoriesRepository: RemoteCategoriesRepository?
    private let movementsRepository: RemoteMovimentiRepository?
    private let transactionsRepository: RemoteTransactionsRepository?
    private let subscriptionsRepository: RemoteSubscriptionsRepository?
    private let recurrencesRepository: RemoteRecurrencesRepository?
    private let upcomingRepository: RemoteUpcomingRepository?
    private let budgetRepository: RemoteBudgetRepository?
    private var didBootstrap = false
    private var bootstrapTask: Task<Void, Never>?
    private var movementTask: Task<Void, Never>?
    private var loadedMovementIDs = Set<UUID>()
    private var loadGeneration = 0

    init(client: APIClient?) {
        isRemoteOnly = client != nil
        if let client {
            bootstrapRepository = RemoteBootstrapRepository(client: client)
            accountsRepository = RemoteAccountsRepository(client: client)
            categoriesRepository = RemoteCategoriesRepository(client: client)
            movementsRepository = RemoteMovimentiRepository(client: client)
            transactionsRepository = RemoteTransactionsRepository(client: client)
            subscriptionsRepository = RemoteSubscriptionsRepository(client: client)
            recurrencesRepository = RemoteRecurrencesRepository(client: client)
            upcomingRepository = RemoteUpcomingRepository(client: client)
            budgetRepository = RemoteBudgetRepository(client: client)
        } else {
            bootstrapRepository = nil
            accountsRepository = nil
            categoriesRepository = nil
            movementsRepository = nil
            transactionsRepository = nil
            subscriptionsRepository = nil
            recurrencesRepository = nil
            upcomingRepository = nil
            budgetRepository = nil
        }
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

    func bootstrapIfNeeded() async {
        guard isRemoteOnly, !didBootstrap else { return }
        if let bootstrapTask {
            await bootstrapTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.bootstrap()
        }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
    }

    func bootstrap() async {
        guard let bootstrapRepository else { return }
        movementTask?.cancel()
        isLoading = true
        errorMessage = nil
        do {
            let response = try await bootstrapRepository.load()
            try Task.checkCancellation()
            profile = response.profile
            accounts = response.accounts
            categories = response.categories
            didBootstrap = true
            normalizeSelectedAccount()
            _ = try await recurrencesRepository?.materialize()
            recurrenceRules = try await recurrencesRepository?.list() ?? []
            _ = try await subscriptionsRepository?.materialize()
            subscriptions = try await subscriptionsRepository?.list() ?? []
            if let selectedAccountID {
                await fetchFirstPage(accountID: selectedAccountID)
            } else {
                clearMovements()
            }
        } catch is CancellationError {
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
        isLoading = false
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
        loadGeneration += 1
        let generation = loadGeneration
        movementTask?.cancel()
        movementTask = Task { [weak self] in
            guard let self else { return }
            await self.fetchFirstPage(accountID: accountID, generation: generation)
        }
    }

    func refresh() async {
        guard let selectedAccountID else { return }
        isRefreshing = true
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
                    weekStart: self.filter == .week ? self.remoteDateOnly(self.selectedWeek) : nil,
                    month: self.filter == .month ? self.remoteMonth(self.selectedMonth) : nil,
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
        filter = newFilter
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

    func createCategory(_ payload: RemoteCategoryCreatePayload) async throws {
        guard let categoriesRepository else { return }
        categories.append(try await categoriesRepository.create(payload))
        categories.sort {
            if $0.income != $1.income { return !$0.income }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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
        await refresh()
        return result
    }

    @discardableResult
    func createRecurrence(_ payload: RemoteRecurrenceCreatePayload) async throws -> RemoteRecurrenceRuleDTO? {
        guard let recurrencesRepository else { return nil }
        let result = try await recurrencesRepository.create(payload)
        _ = try await recurrencesRepository.materialize()
        recurrenceRules = try await recurrencesRepository.list()
        await refresh()
        return result
    }

    @discardableResult
    func updateRecurrence(_ ruleID: UUID, payload: RemoteRecurrenceUpdatePayload) async throws -> RemoteRecurrenceRuleDTO? {
        guard let recurrencesRepository else { return nil }
        let result = try await recurrencesRepository.update(ruleID: ruleID, payload)
        _ = try await recurrencesRepository.materialize()
        recurrenceRules = try await recurrencesRepository.list()
        await refresh()
        return result
    }

    func pauseRecurrence(_ ruleID: UUID) async throws {
        guard let recurrencesRepository else { return }
        _ = try await recurrencesRepository.pause(ruleID: ruleID)
        recurrenceRules = try await recurrencesRepository.list()
    }

    func resumeRecurrence(_ ruleID: UUID) async throws {
        guard let recurrencesRepository else { return }
        _ = try await recurrencesRepository.resume(ruleID: ruleID)
        _ = try await recurrencesRepository.materialize()
        recurrenceRules = try await recurrencesRepository.list()
        await refresh()
    }

    func cancelRecurrence(_ ruleID: UUID) async throws {
        guard let recurrencesRepository else { return }
        _ = try await recurrencesRepository.cancel(ruleID: ruleID)
        recurrenceRules = try await recurrencesRepository.list()
        await refresh()
    }

    @discardableResult
    func updateTransaction(_ transactionID: UUID, payload: RemoteTransactionUpdatePayload) async throws -> RemoteTransactionDTO? {
        guard let transactionsRepository else { return nil }
        let result = try await transactionsRepository.update(transactionID: transactionID, payload)
        await refresh()
        return result
    }

    func deleteTransaction(_ transactionID: UUID) async throws {
        guard let transactionsRepository else { return }
        try await transactionsRepository.delete(transactionID: transactionID)
        await refresh()
    }

    @discardableResult
    func createTransfer(_ payload: RemoteTransferCreatePayload) async throws -> RemoteTransactionDTO? {
        guard let transactionsRepository else { return nil }
        let result = try await transactionsRepository.createTransfer(payload)
        await refresh()
        return result
    }

    func loadSubscriptions() async throws {
        guard let subscriptionsRepository else { return }
        subscriptionErrorMessage = nil
        do {
            _ = try await subscriptionsRepository.materialize()
            subscriptions = try await subscriptionsRepository.list()
        } catch {
            subscriptionErrorMessage = userFacingMessage(for: error)
            throw error
        }
    }

    @discardableResult
    func createSubscription(_ payload: RemoteSubscriptionCreatePayload) async throws -> RemoteSubscriptionDTO? {
        guard let subscriptionsRepository else { return nil }
        let result = try await subscriptionsRepository.create(payload)
        _ = try await subscriptionsRepository.materialize()
        subscriptions = try await subscriptionsRepository.list()
        await refresh()
        return result
    }

    @discardableResult
    func updateSubscription(_ subscriptionID: UUID, payload: RemoteSubscriptionUpdatePayload) async throws -> RemoteSubscriptionDTO? {
        guard let subscriptionsRepository else { return nil }
        let result = try await subscriptionsRepository.update(subscriptionID: subscriptionID, payload)
        _ = try await subscriptionsRepository.materialize()
        subscriptions = try await subscriptionsRepository.list()
        await refresh()
        return result
    }

    func pauseSubscription(_ subscriptionID: UUID) async throws {
        guard let subscriptionsRepository else { return }
        _ = try await subscriptionsRepository.pause(subscriptionID: subscriptionID)
        subscriptions = try await subscriptionsRepository.list()
    }

    func resumeSubscription(_ subscriptionID: UUID) async throws {
        guard let subscriptionsRepository else { return }
        _ = try await subscriptionsRepository.resume(subscriptionID: subscriptionID)
        subscriptions = try await subscriptionsRepository.list()
    }

    func cancelSubscription(_ subscriptionID: UUID) async throws {
        guard let subscriptionsRepository else { return }
        _ = try await subscriptionsRepository.cancel(subscriptionID: subscriptionID)
        subscriptions = try await subscriptionsRepository.list()
    }

    func resetRemoteState() {
        movementTask?.cancel()
        movementTask = nil
        didBootstrap = false
        profile = nil
        accounts = []
        categories = []
        subscriptions = []
        recurrenceRules = []
        upcomingItems = []
        budgetSummary = nil
        budgetErrorMessage = nil
        selectedAccountID = nil
        selectedSnapshot = nil
        clearMovements()
        subscriptionErrorMessage = nil
        errorMessage = nil
    }

    private func fetchFirstPage(accountID: UUID, generation: Int? = nil) async {
        if filter == .upcoming {
            await fetchUpcoming(accountID: accountID, generation: generation)
            return
        }
        guard let movementsRepository else { return }
        let expectedGeneration = generation ?? loadGeneration
        do {
            if filter == .recurring { _ = try await recurrencesRepository?.materialize() }
            let page = try await movementsRepository.page(
                accountID: accountID,
                limit: 50,
                filter: filter.rawValue,
                income: filter == .type ? typeIsIncome : nil,
                day: filter == .day ? remoteDateOnly(selectedDay) : nil,
                weekStart: filter == .week ? remoteDateOnly(selectedWeek) : nil,
                month: filter == .month ? remoteMonth(selectedMonth) : nil,
                categoryID: filter == .category ? selectedCategoryID : nil
            )
            try Task.checkCancellation()
            guard expectedGeneration == loadGeneration, selectedAccountID == accountID else { return }
            selectedSnapshot = page.account
            summary = page.summary
            days = page.days
            nextCursor = page.nextCursor
            loadedMovementIDs = Set(page.days.flatMap(\.movements).map(\.id))
            errorMessage = nil
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
            guard expectedGeneration == loadGeneration, selectedAccountID == accountID else { return }
            upcomingItems = response.items
            clearMovementPageOnly()
            errorMessage = nil
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
    }

    private func resetAndReload() {
        loadGeneration += 1
        movementTask?.cancel()
        guard let selectedAccountID else { clearMovements(); return }
        let generation = loadGeneration
        movementTask = Task { [weak self] in
            guard let self else { return }
            await self.fetchFirstPage(accountID: selectedAccountID, generation: generation)
        }
    }

    private func normalizeSelectedAccount() {
        let valid = selectedAccountID.flatMap { id in activeAccounts.contains(where: { $0.id == id }) ? id : nil }
        let normalized = valid ?? activeAccounts.first?.id
        if selectedAccountID != normalized {
            selectedAccountID = normalized
            loadGeneration += 1
        }
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

    private func remoteMonth(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 2000, components.month ?? 1)
    }

    private func userFacingMessage(for error: Error) -> String {
        if let error = error as? APIError {
            switch error {
            case .unauthorized: return "La sessione è scaduta. Accedi di nuovo."
            case .forbidden: return "Non hai accesso a questi dati."
            case .notFound: return "Il contenuto richiesto non è più disponibile."
            case .validation: return "Controlla i dati inseriti."
            case .server: return "Il servizio non è disponibile. Riprova."
            case .transport: return "Impossibile raggiungere il servizio."
            default: return "Impossibile caricare i dati."
            }
        }
        return "Impossibile caricare i dati."
    }
}
