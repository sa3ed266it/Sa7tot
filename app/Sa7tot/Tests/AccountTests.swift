import CoreData
import XCTest

final class AccountTests: XCTestCase {
    private var contexts: [NSManagedObjectContext] = []
    private static let testModel: NSManagedObjectModel = {
        let bundle = Bundle(for: AccountTests.self)
        guard let modelURL = bundle.url(forResource: "MainModel 5", withExtension: "mom", subdirectory: "MainModel.momd"),
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

    func testExistingExpenseAndIncomeBackfillToStableTypes() throws {
        let context = makeContext()
        let expense = makeTransaction(in: context, account: nil, amount: 10, income: false)
        let income = makeTransaction(in: context, account: nil, amount: 20, income: true)
        try TransactionTypeMigrationService.migrateIfNeeded(in: context, defaults: makeDefaults())
        XCTAssertEqual(expense.wrappedType, .expense)
        XCTAssertEqual(income.wrappedType, .income)
    }

    func testTransactionTypeMigrationIsIdempotent() throws {
        let context = makeContext()
        let defaults = makeDefaults()
        let transaction = makeTransaction(in: context, account: nil, amount: 10)
        let id = transaction.id
        try TransactionTypeMigrationService.migrateIfNeeded(in: context, defaults: defaults)
        try TransactionTypeMigrationService.migrateIfNeeded(in: context, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: TransactionTypeMigrationService.markerKey))
        XCTAssertEqual(try context.count(for: Transaction.fetchRequest()), 1)
        XCTAssertEqual(transaction.id, id)
        XCTAssertEqual(transaction.typeRawValue, TransactionType.expense.rawValue)
    }

    func testTransactionTypeMigrationFailureLeavesMarkerUnsetAndRetrySucceeds() throws {
        let context = makeContext()
        let defaults = makeDefaults()
        _ = makeTransaction(in: context, account: nil, amount: 10)
        let hooks = TransactionTypeMigrationHooks(save: { _ in throw TestError.injected })
        XCTAssertThrowsError(try TransactionTypeMigrationService.migrateIfNeeded(in: context, defaults: defaults, hooks: hooks))
        XCTAssertFalse(defaults.bool(forKey: TransactionTypeMigrationService.markerKey))
        try TransactionTypeMigrationService.migrateIfNeeded(in: context, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: TransactionTypeMigrationService.markerKey))
        XCTAssertEqual(try context.fetch(Transaction.fetchRequest()).filter { $0.typeRawValue == nil }.count, 0)
    }

    func testValidSameCurrencyTransferSavesAsOneNeutralTransaction() throws {
        let context = makeContext()
        let source = makeAccount(in: context, type: .bank, openingBalance: 500)
        let destination = makeAccount(in: context, type: .cash, openingBalance: 20)
        let transfer = makeTransfer(in: context, source: source, destination: destination, amount: 100)
        XCTAssertEqual(transfer.wrappedType, .transfer)
        XCTAssertFalse(transfer.income)
        XCTAssertNil(transfer.category)
        XCTAssertEqual(transfer.account, source)
        XCTAssertEqual(transfer.destinationAccount, destination)
    }

    func testTransferValidationRejectsInvalidAmountIdentityCurrencyAndArchivedAccounts() {
        let context = makeContext()
        let source = makeAccount(in: context, type: .bank)
        let destination = makeAccount(in: context, type: .cash)
        XCTAssertEqual(TransferValidationService.validate(amount: 0, source: source, destination: destination, isCreating: true), .amountMustBePositive)
        XCTAssertEqual(TransferValidationService.validate(amount: -1, source: source, destination: destination, isCreating: true), .amountMustBePositive)
        XCTAssertEqual(TransferValidationService.validate(amount: .infinity, source: source, destination: destination, isCreating: true), .amountMustBeFinite)
        XCTAssertEqual(TransferValidationService.validate(amount: 1, source: source, destination: source, isCreating: true), .sameAccount)
        destination.currencyCode = "USD"
        XCTAssertEqual(TransferValidationService.validate(amount: 1, source: source, destination: destination, isCreating: true), .mixedCurrencies)
        destination.currencyCode = "EUR"
        source.isArchived = true
        XCTAssertEqual(TransferValidationService.validate(amount: 1, source: source, destination: destination, isCreating: true), .sourceArchived)
        source.isArchived = false
        destination.isArchived = true
        XCTAssertEqual(TransferValidationService.validate(amount: 1, source: source, destination: destination, isCreating: true), .destinationArchived)
    }

    func testAssetTransfersChangeSourceAndDestinationBalances() {
        let context = makeContext()
        let source = makeAccount(in: context, type: .bank, openingBalance: 500)
        let destination = makeAccount(in: context, type: .cash, openingBalance: 20)
        let transfer = makeTransfer(in: context, source: source, destination: destination, amount: 100)
        XCTAssertEqual(AccountBalanceService.balance(for: source, transactions: [transfer]), 400)
        XCTAssertEqual(AccountBalanceService.balance(for: destination, transactions: [transfer]), 120)
    }

    func testCreditCardTransferConvention() {
        let context = makeContext()
        let bank = makeAccount(in: context, type: .bank, openingBalance: 1000)
        let card = makeAccount(in: context, type: .creditCard, openingBalance: 500)
        let payment = makeTransfer(in: context, source: bank, destination: card, amount: 200)
        XCTAssertEqual(AccountBalanceService.balance(for: card, transactions: [payment]), 300)
        let outgoing = makeTransfer(in: context, source: card, destination: bank, amount: 50)
        XCTAssertEqual(AccountBalanceService.balance(for: card, transactions: [payment, outgoing]), 350)
        XCTAssertEqual(AccountBalanceService.label(for: card), "Utilizzato")
    }

    func testTransferTotalsBudgetsAndCategoriesAreNeutral() {
        let context = makeContext()
        let source = makeAccount(in: context, type: .bank)
        let destination = makeAccount(in: context, type: .cash)
        let expense = makeTransaction(in: context, account: source, amount: 30)
        let income = makeTransaction(in: context, account: destination, amount: 40, income: true)
        let transfer = makeTransfer(in: context, source: source, destination: destination, amount: 100)
        let transactions = [expense, income, transfer]
        XCTAssertEqual(TransactionTotalsService.expenseTotal(transactions), 30)
        XCTAssertEqual(TransactionTotalsService.incomeTotal(transactions), 40)
        XCTAssertFalse(transfer.isTransfer == false)
        XCTAssertNil(transfer.category)
    }

    func testEditingTransferKeepsUUIDAndUpdatesAllBalanceEffects() {
        let context = makeContext()
        let sourceA = makeAccount(in: context, type: .bank, openingBalance: 500)
        let sourceB = makeAccount(in: context, type: .cash, openingBalance: 100)
        let destinationA = makeAccount(in: context, type: .bank, openingBalance: 0)
        let destinationB = makeAccount(in: context, type: .prepaidCard, openingBalance: 0)
        let transfer = makeTransfer(in: context, source: sourceA, destination: destinationA, amount: 100)
        let id = transfer.id
        TransferService.configure(transfer, amount: 40, source: sourceB, destination: destinationB, note: "Modificato", date: Date())
        XCTAssertEqual(transfer.id, id)
        XCTAssertEqual(AccountBalanceService.balance(for: sourceA, transactions: [transfer]), 500)
        XCTAssertEqual(AccountBalanceService.balance(for: sourceB, transactions: [transfer]), 60)
        XCTAssertEqual(AccountBalanceService.balance(for: destinationA, transactions: [transfer]), 0)
        XCTAssertEqual(AccountBalanceService.balance(for: destinationB, transactions: [transfer]), 40)
    }

    func testDeletingTransferRemovesBothBalanceEffects() {
        let context = makeContext()
        let source = makeAccount(in: context, type: .bank, openingBalance: 100)
        let destination = makeAccount(in: context, type: .cash, openingBalance: 0)
        let transfer = makeTransfer(in: context, source: source, destination: destination, amount: 25)
        context.delete(transfer)
        XCTAssertEqual(AccountBalanceService.balance(for: source, transactions: []), 100)
        XCTAssertEqual(AccountBalanceService.balance(for: destination, transactions: []), 0)
    }

    func testTransferSearchMatchesSourceDestinationAndNote() {
        let context = makeContext()
        let source = makeAccount(in: context, type: .bank)
        source.name = "Revolut"
        let destination = makeAccount(in: context, type: .cash)
        destination.name = "Contanti"
        let transfer = makeTransfer(in: context, source: source, destination: destination, amount: 25, note: "Ricarica")
        XCTAssertTrue(TransactionSearchService.matches(transfer, query: "Revolut"))
        XCTAssertTrue(TransactionSearchService.matches(transfer, query: "Contanti"))
        XCTAssertTrue(TransactionSearchService.matches(transfer, query: "Ricarica"))
    }

    func testTransferCannotBecomeRecurringAndRecurringGeneratorNeverCopiesIt() {
        let context = makeContext()
        let source = makeAccount(in: context, type: .bank)
        let destination = makeAccount(in: context, type: .cash)
        let transfer = makeTransfer(in: context, source: source, destination: destination, amount: 10)
        transfer.recurringType = 3
        TransferService.configure(transfer, amount: 10, source: source, destination: destination, note: nil, date: Date())
        XCTAssertEqual(transfer.recurringType, 0)
        XCTAssertEqual(transfer.wrappedType, .transfer)
    }

    func testManualAndIntentExpenseIncomeSetStableTypes() {
        let expense = makeTransaction(account: makeAccount(type: .bank), amount: 1, income: false)
        let income = makeTransaction(account: makeAccount(type: .bank), amount: 1, income: true)
        XCTAssertEqual(expense.wrappedType, .expense)
        XCTAssertEqual(income.wrappedType, .income)
    }

    func testMalformedHistoricalTransferDoesNotCrashBalanceOrSearch() {
        let context = makeContext()
        let source = makeAccount(in: context, type: .bank, openingBalance: 10)
        let malformed = makeTransaction(in: context, account: source, amount: 5)
        malformed.typeRawValue = TransactionType.transfer.rawValue
        malformed.destinationAccount = nil
        XCTAssertEqual(AccountBalanceService.balance(for: source, transactions: [malformed]), 5)
        XCTAssertTrue(TransactionSearchService.matches(malformed, query: ""))
    }

    func testWalletAmountParserAcceptsItalianEnglishAndCurrencyForms() throws {
        XCTAssertEqual(try WalletAmountParser.parse("12,50"), Decimal(string: "12.50"))
        XCTAssertEqual(try WalletAmountParser.parse("12.50"), Decimal(string: "12.50"))
        XCTAssertEqual(try WalletAmountParser.parse("€12,50"), Decimal(string: "12.50"))
        XCTAssertEqual(try WalletAmountParser.parse("12,50 €"), Decimal(string: "12.50"))
        XCTAssertEqual(try WalletAmountParser.parse("EUR 12.50"), Decimal(string: "12.50"))
        XCTAssertEqual(try WalletAmountParser.parse("1.234,56"), Decimal(string: "1234.56"))
        XCTAssertEqual(try WalletAmountParser.parse("1,234.56"), Decimal(string: "1234.56"))
    }

    func testWalletAmountParserRejectsEmptyZeroNegativeAndMalformed() {
        for input in ["", "0", "0,00", "-1", "12,3,4", "EUR"] {
            XCTAssertThrowsError(try WalletAmountParser.parse(input), input)
        }
    }

    func testWalletAccountMappingNormalizesAndRejectsDuplicatesAndArchivedAccounts() throws {
        let context = makeContext()
        let revolut = makeAccount(in: context, type: .bank)
        let other = makeAccount(in: context, type: .cash)
        revolut.walletLabel = "  Revolút  "
        XCTAssertEqual(try WalletAccountResolver.resolve(label: "revolut", accounts: [revolut, other]), revolut)
        other.walletLabel = "REVOLUT"
        XCTAssertThrowsError(try WalletAccountResolver.validateUnique(label: other.walletLabel, account: other, accounts: [revolut, other]))
        other.walletLabel = nil
        revolut.isArchived = true
        XCTAssertThrowsError(try WalletAccountResolver.resolve(label: "Revolut", accounts: [revolut, other]))
    }

    func testWalletMappingWithoutLabelRequiresExplicitFallback() {
        let account = makeAccount(type: .bank)
        XCTAssertThrowsError(try WalletAccountResolver.resolve(label: nil, accounts: [account]))
        XCTAssertEqual(try? WalletAccountResolver.resolve(label: nil, accounts: [account], fallback: account), account)
    }

    func testMerchantCategorizationKnownGroceryAndUnknownNeedsReview() {
        let context = makeContext()
        let grocery = makeCategory(in: context, name: "Alimentari")
        let unknown = MerchantCategorizationService.result(merchant: "Esselunga Milano", categories: [grocery])
        if case let .matched(category) = unknown { XCTAssertEqual(category, grocery) } else { XCTFail("Known merchant should be categorized") }
        if case .needsReview = MerchantCategorizationService.result(merchant: "Negozio sconosciuto", categories: [grocery]) {} else { XCTFail("Unknown merchant needs review") }
    }

    func testWalletDuplicateDetectorUsesReferenceAndTenMinuteFingerprint() {
        let context = makeContext()
        let account = makeAccount(in: context, type: .bank)
        let transaction = makeTransaction(in: context, account: account, amount: 12.5)
        transaction.originRawValue = TransactionOrigin.walletShortcut.rawValue
        transaction.merchant = "Esselunga"
        transaction.externalReference = "wallet-1"
        XCTAssertTrue(WalletDuplicateDetector.isDuplicate(amount: Decimal(string: "12.5")!, merchant: "Altro", account: account, date: Date(), externalReference: "wallet-1", transactions: [transaction]))
        transaction.externalReference = nil
        XCTAssertTrue(WalletDuplicateDetector.isDuplicate(amount: Decimal(string: "12.5")!, merchant: "esselunga", account: account, date: Date().addingTimeInterval(300), externalReference: nil, transactions: [transaction]))
        XCTAssertFalse(WalletDuplicateDetector.isDuplicate(amount: Decimal(string: "12.5")!, merchant: "esselunga", account: account, date: Date().addingTimeInterval(601), externalReference: nil, transactions: [transaction]))
    }

    func testCategoryIconDescriptorRoundTripsSupportedIdentifiers() {
        XCTAssertEqual(CategoryIconDescriptor(identifier: "sf:tram.fill"), .sfSymbol("tram.fill"))
        XCTAssertEqual(CategoryIconDescriptor(identifier: "asset:netflix"), .asset("netflix"))
        XCTAssertEqual(CategoryIconDescriptor(identifier: "logo:spotify"), .appLogo("spotify"))
        XCTAssertEqual(CategoryIconDescriptor(identifier: "logo:spotify").identifier, "logo:spotify")
    }

    func testCategoryIconDescriptorFallsBackForInvalidIdentifiers() {
        XCTAssertEqual(CategoryIconDescriptor(identifier: "invalid"), .fallback)
        XCTAssertEqual(CategoryIconPresentation.descriptor(for: "sf:not.a.real.symbol"), .fallback)
    }

    func testCategoryIconCatalogHasUniqueIdentifiers() {
        let identifiers = CategoryIconCatalog.all.map(\.id)
        XCTAssertEqual(identifiers.count, Set(identifiers).count)
    }

    func testCategoryIconColorIsSeparateFromPresentationStyle() {
        XCTAssertEqual(CategoryIconPresentation.Style.plain, .plain)
        XCTAssertNotEqual(CategoryIconPresentation.Style.plain, .selection)
    }

    func testNewCategoryUsesCleanIconIdentifierDefault() {
        let context = makeContext()
        let category = Category(context: context)
        XCTAssertEqual(category.iconIdentifier, "sf:tag.fill")
    }

    private func makeCategory(in context: NSManagedObjectContext, name: String, income: Bool = false) -> Category {
        let category = Category(context: context)
        category.id = UUID()
        category.name = name
        category.income = income
        category.iconIdentifier = "sf:doc.text.fill"
        category.colour = "#5E7CE2"
        category.dateCreated = Date()
        return category
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

    private func makeTransfer(in context: NSManagedObjectContext, source: Account, destination: Account, amount: Double, note: String? = nil) -> Transaction {
        let transaction = Transaction(context: context)
        transaction.id = UUID()
        TransferService.configure(transaction, amount: amount, source: source, destination: destination, note: note, date: Date())
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
