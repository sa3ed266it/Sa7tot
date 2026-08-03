import CoreData
import XCTest

final class AccountTests: XCTestCase {
    private var contexts: [NSManagedObjectContext] = []
    private static let testModel: NSManagedObjectModel = {
        let bundle = Bundle(for: AccountTests.self)
        guard let modelURL = bundle.url(forResource: "MainModel 3", withExtension: "mom", subdirectory: "MainModel.momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Test model not bundled")
        }
        return model
    }()

    override func tearDown() {
        contexts.removeAll()
        super.tearDown()
    }

    func testAccountTypeRawValuesAndItalianLabels() {
        XCTAssertEqual(AccountType.creditCard.rawValue, "creditCard")
        XCTAssertEqual(AccountType.creditCard.italianName, "Carta di credito")
        XCTAssertTrue(AccountType.creditCard.isCredit)
        XCTAssertEqual(AccountBalanceService.label(for: makeAccount(type: .creditCard)), "Utilizzato")
    }

    func testDefaultAccountIsCreatedExactlyOnce() throws {
        let context = makeContext()
        let defaults = makeDefaults()

        try AccountMigrationService.migrateIfNeeded(in: context, currencyCode: "EUR", defaults: defaults)
        try AccountMigrationService.migrateIfNeeded(in: context, currencyCode: "EUR", defaults: defaults)

        XCTAssertEqual(try context.count(for: Account.fetchRequest()), 1)
        XCTAssertEqual(try context.fetch(Account.fetchRequest()).first?.name, "Conto principale")
    }

    func testMigrationIsIdempotentAcrossRepeatedRuns() throws {
        let context = makeContext()
        let defaults = makeDefaults()
        let transaction = makeTransaction(in: context, account: nil, amount: 10)
        let id = transaction.id

        try AccountMigrationService.migrateIfNeeded(in: context, currencyCode: "EUR", defaults: defaults)
        try AccountMigrationService.migrateIfNeeded(in: context, currencyCode: "EUR", defaults: defaults)

        XCTAssertEqual(try context.count(for: Account.fetchRequest()), 1)
        XCTAssertEqual(try context.count(for: Transaction.fetchRequest()), 1)
        XCTAssertEqual(try context.fetch(Transaction.fetchRequest()).first?.id, id)
    }

    func testNilTransactionsAndTemplatesReceiveDefaultAccount() throws {
        let context = makeContext()
        let defaults = makeDefaults()
        let transaction = makeTransaction(in: context, account: nil, amount: 10)
        let template = makeTemplate(in: context, account: nil)

        try AccountMigrationService.migrateIfNeeded(in: context, currencyCode: "EUR", defaults: defaults)

        XCTAssertNotNil(transaction.account)
        XCTAssertNotNil(template.account)
        XCTAssertEqual(transaction.account, template.account)
    }

    func testAssetExpenseLowersBalanceAndIncomeRaisesIt() {
        let account = makeAccount(type: .bank, openingBalance: 100)
        let expense = makeTransaction(account: account, amount: 25, income: false)
        let income = makeTransaction(account: account, amount: 80, income: true)

        XCTAssertEqual(AccountBalanceService.balance(for: account, transactions: [expense]), 75)
        XCTAssertEqual(AccountBalanceService.balance(for: account, transactions: [expense, income]), 155)
    }

    func testCreditCardDebtUsesOpeningPlusExpensesMinusCredits() {
        XCTAssertEqual(AccountBalanceService.balance(openingBalance: 500, type: .creditCard, income: 100, expenses: 350), 750)
    }

    func testChangingTransactionAccountUpdatesBothBalances() {
        let context = makeContext()
        let accountA = makeAccount(in: context, type: .bank, openingBalance: 100)
        let accountB = makeAccount(in: context, type: .bank, openingBalance: 200)
        let transaction = makeTransaction(in: context, account: accountA, amount: 40, income: false)

        XCTAssertEqual(AccountBalanceService.balance(for: accountA, transactions: [transaction]), 60)
        transaction.account = accountB
        XCTAssertEqual(AccountBalanceService.balance(for: accountA, transactions: [transaction]), 100)
        XCTAssertEqual(AccountBalanceService.balance(for: accountB, transactions: [transaction]), 160)
    }

    func testArchivedAccountsAreExcludedFromDefaultSelection() throws {
        let context = makeContext()
        let archived = makeAccount(in: context, type: .bank)
        archived.isArchived = true
        let active = makeAccount(in: context, type: .cash)

        XCTAssertEqual(AccountMigrationService.defaultActiveAccount(in: context), active)
    }

    func testAccountWithTransactionHistoryCannotBeDeleted() {
        let account = makeAccount(type: .bank)
        _ = makeTransaction(account: account, amount: 1)
        XCTAssertFalse(account.canDelete)
    }

    func testAccountWithTemplateHistoryCannotBeDeleted() {
        let context = makeContext()
        let account = makeAccount(in: context, type: .bank)
        _ = makeTemplate(in: context, account: account)
        XCTAssertFalse(account.canDelete)
    }

    func testEmptyAccountCanBeDeleted() {
        XCTAssertTrue(makeAccount(type: .other).canDelete)
    }

    func testGeneratedRecurringTransactionInheritsTemplateAccount() throws {
        let context = makeContext()
        let account = makeAccount(in: context, type: .bank)
        let template = makeTemplate(in: context, account: account)
        let generated = makeTransaction(in: context, account: AccountAssignmentService.inheritedAccount(from: template), amount: 5)

        XCTAssertEqual(generated.account, account)
    }

    func testMigrationSaveFailureLeavesMarkerUnsetAndObjectsIntact() throws {
        let context = makeContext()
        let defaults = makeDefaults()
        let transaction = makeTransaction(in: context, account: nil, amount: 12)
        let id = transaction.id
        try context.save()
        let hooks = AccountMigrationHooks(save: { _ in throw TestError.injected }, verify: nil)

        XCTAssertThrowsError(try AccountMigrationService.migrateIfNeeded(in: context, currencyCode: "EUR", defaults: defaults, hooks: hooks))
        XCTAssertFalse(defaults.bool(forKey: AccountMigrationService.markerKey))
        XCTAssertEqual(try context.count(for: Account.fetchRequest()), 0)
        XCTAssertEqual(try context.fetch(Transaction.fetchRequest()).first?.id, id)
    }

    func testMigrationRetryAfterFailureCreatesOneDefaultAccount() throws {
        let context = makeContext()
        let defaults = makeDefaults()
        let hooks = AccountMigrationHooks(save: { _ in throw TestError.injected }, verify: nil)

        XCTAssertThrowsError(try AccountMigrationService.migrateIfNeeded(in: context, currencyCode: "EUR", defaults: defaults, hooks: hooks))
        try AccountMigrationService.migrateIfNeeded(in: context, currencyCode: "EUR", defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: AccountMigrationService.markerKey))
        XCTAssertEqual(try context.count(for: Account.fetchRequest()), 1)
    }

    func testMigrationVerificationFailureLeavesMarkerUnsetAndRetryIsIdempotent() throws {
        let context = makeContext()
        let defaults = makeDefaults()
        let hooks = AccountMigrationHooks(save: nil, verify: { _ in throw TestError.injected })

        XCTAssertThrowsError(try AccountMigrationService.migrateIfNeeded(in: context, currencyCode: "EUR", defaults: defaults, hooks: hooks))
        XCTAssertFalse(defaults.bool(forKey: AccountMigrationService.markerKey))
        XCTAssertEqual(try context.count(for: Account.fetchRequest()), 1)
        try AccountMigrationService.migrateIfNeeded(in: context, currencyCode: "EUR", defaults: defaults)
        XCTAssertEqual(try context.count(for: Account.fetchRequest()), 1)
    }

    func testNewManualExpenseAlwaysReceivesAnAccount() throws {
        let context = makeContext()
        try AccountMigrationService.migrateIfNeeded(in: context, currencyCode: "EUR", defaults: makeDefaults())
        let transaction = makeTransaction(in: context, account: nil, amount: 20)

        XCTAssertNotNil(AccountAssignmentService.assignDefault(to: transaction, in: context))
        XCTAssertNotNil(transaction.account)
    }

    func testNewManualIncomeAlwaysReceivesAnAccount() throws {
        let context = makeContext()
        try AccountMigrationService.migrateIfNeeded(in: context, currencyCode: "EUR", defaults: makeDefaults())
        let transaction = makeTransaction(in: context, account: nil, amount: 20, income: true)

        _ = AccountAssignmentService.assignDefault(to: transaction, in: context)
        XCTAssertNotNil(transaction.account)
    }

    func testAppIntentCreationPathUsesDefaultAccount() throws {
        let context = makeContext()
        try AccountMigrationService.migrateIfNeeded(in: context, currencyCode: "EUR", defaults: makeDefaults())
        let transaction = makeTransaction(in: context, account: nil, amount: 20)

        _ = AccountAssignmentService.assignDefault(to: transaction, in: context)
        XCTAssertEqual(transaction.account?.name, "Conto principale")
    }

    func testAccountCurrencyCannotChangeAfterHistoryExists() {
        let context = makeContext()
        let account = makeAccount(in: context, type: .bank)
        _ = makeTransaction(in: context, account: account, amount: 1)
        XCTAssertFalse(account.canChangeCurrency)
    }

    func testAccountCurrencyCanChangeWithoutHistory() {
        XCTAssertTrue(makeAccount(type: .bank).canChangeCurrency)
    }

    func testNoFinancialValuesAreIncludedInMigrationErrors() {
        let message = AccountMigrationError.verificationFailed(expectedTransactions: 2, actualTransactions: 1).localizedDescription
        XCTAssertFalse(message.contains("12.50"))
        XCTAssertFalse(message.contains("1000"))
    }

    private func makeContext() -> NSManagedObjectContext {
        let container = NSPersistentContainer(name: "AccountTests", managedObjectModel: Self.testModel)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { fatalError("Unable to load in-memory store: \(loadError)") }
        contexts.append(container.viewContext)
        return container.viewContext
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "Sa7tot.AccountTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeAccount(type: AccountType, openingBalance: Double = 0) -> Account {
        let context = makeContext()
        return makeAccount(in: context, type: type, openingBalance: openingBalance)
    }

    private func makeAccount(in context: NSManagedObjectContext, type: AccountType, openingBalance: Double = 0) -> Account {
        let account = Account(context: context)
        account.id = UUID()
        account.name = type.italianName
        account.typeRawValue = type.rawValue
        account.openingBalance = openingBalance
        account.currencyCode = "EUR"
        account.iconName = "building.columns.fill"
        account.colour = "#5E7CE2"
        account.isArchived = false
        account.createdAt = Date()
        return account
    }

    private func makeTransaction(in context: NSManagedObjectContext? = nil, account: Account?, amount: Double, income: Bool = false) -> Transaction {
        let context = context ?? account?.managedObjectContext ?? makeContext()
        let transaction = Transaction(context: context)
        transaction.id = UUID()
        transaction.account = account
        transaction.amount = amount
        transaction.income = income
        transaction.date = Date()
        transaction.day = Date()
        transaction.month = Date()
        return transaction
    }

    private func makeTemplate(in context: NSManagedObjectContext, account: Account?) -> TemplateTransaction {
        let template = TemplateTransaction(context: context)
        template.id = UUID()
        template.account = account
        template.amount = 5
        template.income = false
        template.recurringType = 2
        template.recurringCoefficient = 1
        return template
    }

    private enum TestError: Error { case injected }
}
