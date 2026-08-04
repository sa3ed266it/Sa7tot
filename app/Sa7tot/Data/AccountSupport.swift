import CoreData
import Foundation

enum PersistenceSaveCoordinator {
    @discardableResult
    static func save(
        context: NSManagedObjectContext,
        onSuccess: () -> Void = {}
    ) throws -> Bool {
        guard context.hasChanges else { return false }
        try context.save()
        onSuccess()
        return true
    }
}

enum StatisticsTransactionFilter {
    static func excludingTransfersPredicate() -> NSPredicate {
        NSPredicate(
            format: "%K != %@ OR %K == nil",
            #keyPath(Transaction.typeRawValue),
            TransactionType.transfer.rawValue,
            #keyPath(Transaction.typeRawValue)
        )
    }
}

enum InsightsPeriod: Int, CaseIterable {
    case week = 1
    case month = 2
    case year = 3
}
import UserNotifications

enum AccountType: String, CaseIterable, Identifiable {
    case cash
    case bank
    case debitCard
    case creditCard
    case prepaidCard
    case savings
    case other

    var id: String { rawValue }

    var italianName: String {
        switch self {
        case .cash: return "Contanti"
        case .bank: return "Conto bancario"
        case .debitCard: return "Carta di debito"
        case .creditCard: return "Carta di credito"
        case .prepaidCard: return "Carta prepagata"
        case .savings: return "Risparmi"
        case .other: return "Altro"
        }
    }

    var isCredit: Bool { self == .creditCard }
}

enum AccountMigrationError: LocalizedError {
    case noAccountCreated
    case verificationFailed(expectedTransactions: Int, actualTransactions: Int)
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noAccountCreated: return "Impossibile creare il conto principale."
        case let .verificationFailed(expected, actual):
            return "Migrazione conti incompleta: attesi \(expected) movimenti, trovati \(actual)."
        case let .saveFailed(error): return "Impossibile salvare la migrazione dei conti: \(error.localizedDescription)"
        }
    }
}

enum AccountSaveError: LocalizedError {
    case persistence(Error)

    var errorDescription: String? {
        switch self {
        case let .persistence(error): return "Impossibile salvare le modifiche al conto: \(error.localizedDescription)"
        }
    }
}

struct AccountMigrationHooks {
    var save: ((NSManagedObjectContext) throws -> Void)?
    var verify: ((NSManagedObjectContext) throws -> Void)?

    static let production = AccountMigrationHooks(save: nil, verify: nil)
}

enum AccountQuery {
    static let activePredicate = NSPredicate(format: "isArchived = NO")

    static func isActive(_ account: Account) -> Bool {
        account.managedObjectContext != nil && !account.isDeleted && !account.isArchived
    }

    static func activeAccounts(from accounts: some Sequence<Account>) -> [Account] {
        accounts.filter(isActive)
    }

    static func resolvedSelection(current: Account?, from accounts: some Sequence<Account>) -> Account? {
        let active = activeAccounts(from: accounts)
        if let current, active.contains(where: { $0.objectID == current.objectID }) {
            return current
        }
        return active.first
    }

    /// Normalizes the editor's account binding without inventing a selection.
    /// A single active account is the only case where the editor may select for
    /// the user; with multiple accounts, a valid existing selection is kept and
    /// an empty selection remains empty until the user chooses one.
    static func normalizedEditorSelection(current: Account?, from accounts: some Sequence<Account>) -> Account? {
        let active = activeAccounts(from: accounts)
        if let current, active.contains(where: { $0.objectID == current.objectID }) {
            return current
        }
        return active.count == 1 ? active[0] : nil
    }
}

enum AccountMigrationService {
    static let markerKey = "accountsMigrationV1Complete"
    static let defaultAccountName = "Conto principale"

    static func migrateIfNeeded(in context: NSManagedObjectContext, currencyCode: String, defaults: UserDefaults, hooks: AccountMigrationHooks = .production) throws {
        guard !defaults.bool(forKey: markerKey) else { return }

        try context.performAndWait {
            let accountRequest = Account.fetchRequest()
            accountRequest.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
            let accounts = try context.fetch(accountRequest)
            let account: Account

            if let existing = accounts.first(where: { $0.name == defaultAccountName && AccountQuery.isActive($0) }) {
                account = existing
            } else if let existing = accounts.first(where: AccountQuery.isActive) {
                account = existing
            } else {
                let newAccount = Account(context: context)
                newAccount.id = UUID()
                newAccount.name = defaultAccountName
                newAccount.typeRawValue = AccountType.bank.rawValue
                newAccount.openingBalance = 0
                newAccount.currencyCode = currencyCode
                newAccount.iconName = "building.columns.fill"
                newAccount.colour = "#5E7CE2"
                newAccount.isArchived = false
                newAccount.createdAt = Date()
                newAccount.order = 0
                account = newAccount
            }

            let transactionRequest = Transaction.fetchRequest()
            let transactions = try context.fetch(transactionRequest)
            let originalCount = transactions.count
            transactions.filter { $0.account == nil }.forEach { $0.account = account }

            let templateRequest = TemplateTransaction.fetchRequest()
            let templates = try context.fetch(templateRequest)
            templates.filter { $0.account == nil }.forEach { $0.account = account }

            do {
                if let save = hooks.save {
                    try save(context)
                } else {
                    try context.save()
                }
            } catch {
                context.rollback()
                throw AccountMigrationError.saveFailed(error)
            }

            if let verify = hooks.verify {
                try verify(context)
            }

            let verifyRequest = Transaction.fetchRequest()
            let verifiedTransactions = try context.fetch(verifyRequest)
            let missingTransactions = verifiedTransactions.filter { $0.account == nil }.count
            let accountCount = try context.count(for: accountRequest)
            guard originalCount == verifiedTransactions.count, missingTransactions == 0, accountCount > 0 else {
                throw AccountMigrationError.verificationFailed(expectedTransactions: originalCount, actualTransactions: verifiedTransactions.count)
            }
        }

        defaults.set(true, forKey: markerKey)
    }

    static func defaultActiveAccount(in context: NSManagedObjectContext) -> Account? {
        let request = Account.fetchRequest()
        request.predicate = AccountQuery.activePredicate
        request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
        return try? context.fetch(request).first
    }
}

enum AccountAssignmentService {
    static func assignDefault(to transaction: Transaction, in context: NSManagedObjectContext) -> Account? {
        let account = AccountMigrationService.defaultActiveAccount(in: context)
        transaction.account = account
        return account
    }

    static func inheritedAccount(from template: TemplateTransaction, replacement: Account? = nil) -> Account? {
        template.account ?? replacement
    }
}

enum AccountBalanceService {
    static func balance(openingBalance: Double, type: AccountType, income: Double, expenses: Double) -> Double {
        type.isCredit ? openingBalance + expenses - income : openingBalance + income - expenses
    }

    static func balance(for account: Account, transactions: some Sequence<Transaction>) -> Double {
        var total = account.openingBalance
        for transaction in transactions {
            guard transaction.account == account || transaction.destinationAccount == account else { continue }
            switch transaction.wrappedType {
            case .expense:
                total += account.wrappedType.isCredit ? transaction.amount : -transaction.amount
            case .income:
                total += account.wrappedType.isCredit ? -transaction.amount : transaction.amount
            case .transfer:
                if transaction.account == account {
                    total += account.wrappedType.isCredit ? transaction.amount : -transaction.amount
                } else if transaction.destinationAccount == account {
                    total += account.wrappedType.isCredit ? -transaction.amount : transaction.amount
                }
            }
        }
        return total
    }

    static func label(for account: Account) -> String {
        AccountType(rawValue: account.typeRawValue ?? "")?.isCredit == true ? "Utilizzato" : "Saldo"
    }
}

extension Account {
    var wrappedType: AccountType { AccountType(rawValue: typeRawValue ?? "") ?? .other }
    var wrappedColour: String { (colour ?? "").isEmpty ? "#5E7CE2" : (colour ?? "#5E7CE2") }
    var transactionSet: Set<Transaction> { transactions as? Set<Transaction> ?? [] }
    var templateSet: Set<TemplateTransaction> { templateTransactions as? Set<TemplateTransaction> ?? [] }
    var canDelete: Bool { transactionSet.isEmpty && templateSet.isEmpty }
    var canChangeCurrency: Bool { canDelete }

    var normalizedWalletLabel: String? {
        WalletTextNormalizer.normalize(walletLabel)
    }
}

enum TransactionOrigin: String {
    case manual
    case shortcut
    case walletShortcut
    case importFile
}

enum TransactionReviewStatus: String {
    case confirmed
    case needsReview
}

extension Transaction {
    var wrappedOrigin: TransactionOrigin {
        TransactionOrigin(rawValue: originRawValue ?? "") ?? .manual
    }

    var wrappedReviewStatus: TransactionReviewStatus {
        TransactionReviewStatus(rawValue: reviewStatusRawValue ?? "") ?? .confirmed
    }

    var wrappedMerchant: String { merchant ?? "" }
}

enum WalletTextNormalizer {
    static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let folded = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
        let cleaned = folded.unicodeScalars.map { scalar -> String in
            let value = String(scalar)
            return value.rangeOfCharacter(from: .alphanumerics) != nil ? value : " "
        }.joined()
        let result = cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return result.isEmpty ? nil : result
    }
}

enum WalletAmountParserError: LocalizedError, Equatable {
    case empty
    case malformed
    case nonPositive

    var errorDescription: String? {
        switch self {
        case .empty: return "Importo non valido: inserisci un importo."
        case .malformed: return "Importo non valido: formato non riconosciuto."
        case .nonPositive: return "Importo non valido: deve essere maggiore di zero."
        }
    }
}

enum WalletAmountParser {
    static func parse(_ raw: String) throws -> Decimal {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw WalletAmountParserError.empty }
        guard !value.contains("-") else { throw WalletAmountParserError.nonPositive }

        value = value.replacingOccurrences(of: "€", with: "")
        value = value.replacingOccurrences(of: "EUR", with: "", options: .caseInsensitive)
        value = value.replacingOccurrences(of: " ", with: "")
        guard !value.isEmpty, value.range(of: "^[0-9.,]+$", options: .regularExpression) != nil else {
            throw WalletAmountParserError.malformed
        }

        let commaCount = value.filter { $0 == "," }.count
        let dotCount = value.filter { $0 == "." }.count
        let normalized: String

        if commaCount > 1 || dotCount > 1 {
            throw WalletAmountParserError.malformed
        } else if commaCount == 1 && dotCount == 1 {
            guard let comma = value.lastIndex(of: ","), let dot = value.lastIndex(of: ".") else {
                throw WalletAmountParserError.malformed
            }
            let decimalSeparator = comma > dot ? "," : "."
            let groupingSeparator = decimalSeparator == "," ? "." : ","
            let parts = value.split(separator: Character(decimalSeparator), omittingEmptySubsequences: false)
            guard parts.count == 2, parts[1].count == 1 || parts[1].count == 2 else {
                throw WalletAmountParserError.malformed
            }
            normalized = String(parts[0]).replacingOccurrences(of: groupingSeparator, with: "") + "." + String(parts[1])
        } else if commaCount == 1 || dotCount == 1 {
            let separator: Character = commaCount == 1 ? "," : "."
            let parts = value.split(separator: separator, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                throw WalletAmountParserError.malformed
            }
            if parts[1].count == 3 {
                normalized = String(parts[0]) + String(parts[1])
            } else if parts[1].count <= 2 {
                normalized = String(parts[0]) + "." + String(parts[1])
            } else {
                throw WalletAmountParserError.malformed
            }
        } else {
            normalized = value
        }

        guard let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), decimal > 0 else {
            throw WalletAmountParserError.nonPositive
        }
        return decimal
    }
}

enum WalletAccountResolutionError: LocalizedError, Equatable {
    case unmapped(String)
    case noFallback
    case archived
    case duplicate

    var errorDescription: String? {
        switch self {
        case let .unmapped(label): return "Nessun conto è collegato alla carta “(label)”."
        case .noFallback: return "Nessun conto Wallet configurato come fallback."
        case .archived: return "Il conto Wallet configurato è archiviato."
        case .duplicate: return "Questa etichetta Wallet è già collegata a un altro conto attivo."
        }
    }
}

enum WalletAccountResolver {
    static func resolve(label: String?, accounts: [Account], fallback: Account? = nil) throws -> Account {
        if let normalized = WalletTextNormalizer.normalize(label) {
            let matches = accounts.filter { !$0.isArchived && $0.normalizedWalletLabel == normalized }
            guard matches.count == 1 else {
                if matches.count > 1 { throw WalletAccountResolutionError.duplicate }
                throw WalletAccountResolutionError.unmapped(label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            }
            return matches[0]
        }
        guard let fallback else { throw WalletAccountResolutionError.noFallback }
        guard !fallback.isArchived else { throw WalletAccountResolutionError.archived }
        return fallback
    }

    static func validateUnique(label: String?, account: Account, accounts: [Account]) throws {
        guard let normalized = WalletTextNormalizer.normalize(label) else { return }
        let duplicate = accounts.contains { other in
            other != account && !other.isArchived && other.normalizedWalletLabel == normalized
        }
        if duplicate { throw WalletAccountResolutionError.duplicate }
    }
}

enum MerchantCategorizationResult {
    case matched(Category)
    case needsReview(Category?)
}

enum MerchantCategorizationService {
    private static let rules: [(keywords: [String], categoryNames: [String])] = [
        (["esselunga", "lidl", "carrefour", "conad", "aldi"], ["Alimentari", "Cibo"]),
        (["mcdonald", "burger king", "kfc", "ristorante", "restaurant"], ["Ristoranti", "Cibo"]),
        (["trenitalia", "italo", "atm milano", "metro", "taxi"], ["Trasporti"]),
        (["amazon", "zara", "h&m", "apple store"], ["Shopping"]),
        (["netflix", "spotify", "cinema"], ["Intrattenimento"]),
        (["farmacia"], ["Salute"]),
        (["ikea", "leroy merlin"], ["Casa"]),
        (["enel", "a2a", "tim", "vodafone"], ["Bollette"]),
        (["ryanair", "easyjet", "booking"], ["Viaggi"])
    ]

    static func result(merchant: String?, categories: [Category]) -> MerchantCategorizationResult {
        let normalized = WalletTextNormalizer.normalize(merchant) ?? ""
        let fallback = categories.first
        guard !normalized.isEmpty else { return .needsReview(fallback) }

        for rule in rules where rule.keywords.contains(where: { normalized.contains($0) }) {
            if let category = rule.categoryNames.compactMap({ name in
                categories.first(where: { WalletTextNormalizer.normalize($0.name) == WalletTextNormalizer.normalize(name) })
            }).first {
                return .matched(category)
            }
            return .needsReview(fallback)
        }
        return .needsReview(fallback)
    }
}

struct WalletFingerprint: Hashable {
    let accountID: UUID
    let merchant: String
    let amount: Decimal
    let bucket: Int
    let origin: TransactionOrigin
}

enum WalletDuplicateDetector {
    static func isDuplicate(amount: Decimal, merchant: String?, account: Account, date: Date, externalReference: String?, transactions: some Sequence<Transaction>) -> Bool {
        let normalizedMerchant = WalletTextNormalizer.normalize(merchant) ?? ""
        let origin = TransactionOrigin.walletShortcut.rawValue
        if let reference = externalReference?.trimmingCharacters(in: .whitespacesAndNewlines), !reference.isEmpty {
            return transactions.contains { $0.wrappedOrigin == .walletShortcut && $0.externalReference == reference }
        }
        return transactions.contains { transaction in
            guard transaction.wrappedOrigin.rawValue == origin,
                  transaction.account == account,
                  transaction.amount == NSDecimalNumber(decimal: amount).doubleValue,
                  WalletTextNormalizer.normalize(transaction.merchant) == normalizedMerchant,
                  let transactionDate = transaction.date else { return false }
            return abs(transactionDate.timeIntervalSince(date)) <= 600
        }
    }
}

enum WalletAutomationError: LocalizedError {
    case invalidAmount(String)
    case unmappedAccount(String)
    case duplicate
    case persistence

    var errorDescription: String? {
        switch self {
        case let .invalidAmount(message): return message
        case let .unmappedAccount(message): return message
        case .duplicate: return "Questa spesa risulta già registrata."
        case .persistence: return "Impossibile registrare la spesa. Controlla l’automazione Wallet e riprova."
        }
    }
}

enum WalletNotificationService {
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func notify(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

enum TransactionType: String, CaseIterable {
    case expense
    case income
    case transfer
}

enum TransferValidationError: LocalizedError, Equatable {
    case missingSource
    case missingDestination
    case sameAccount
    case amountMustBePositive
    case amountMustBeFinite
    case mixedCurrencies
    case sourceArchived
    case destinationArchived

    var errorDescription: String? {
        switch self {
        case .missingSource: return "Seleziona il conto di origine."
        case .missingDestination: return "Seleziona il conto di destinazione."
        case .sameAccount: return "Il conto di origine e quello di destinazione devono essere diversi."
        case .amountMustBePositive: return "L'importo del trasferimento deve essere maggiore di zero."
        case .amountMustBeFinite: return "Inserisci un importo valido."
        case .mixedCurrencies: return "I trasferimenti tra valute diverse non sono ancora supportati."
        case .sourceArchived: return "Il conto di origine è archiviato e non può ricevere nuovi trasferimenti."
        case .destinationArchived: return "Il conto di destinazione è archiviato e non può ricevere nuovi trasferimenti."
        }
    }
}

enum TransferValidationService {
    static func validate(amount: Double, source: Account?, destination: Account?, isCreating: Bool) -> TransferValidationError? {
        guard source != nil else { return .missingSource }
        guard destination != nil else { return .missingDestination }
        guard amount.isFinite else { return .amountMustBeFinite }
        guard amount > 0 else { return .amountMustBePositive }
        guard source != destination else { return .sameAccount }
        guard source?.currencyCode == destination?.currencyCode else { return .mixedCurrencies }
        if isCreating {
            if source?.isArchived == true { return .sourceArchived }
            if destination?.isArchived == true { return .destinationArchived }
        }
        return nil
    }
}

enum TransferService {
    static func configure(_ transaction: Transaction, amount: Double, source: Account, destination: Account, note: String?, date: Date) {
        transaction.typeRawValue = TransactionType.transfer.rawValue
        transaction.income = false
        transaction.amount = amount
        transaction.account = source
        transaction.destinationAccount = destination
        transaction.category = nil
        transaction.note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.date = date
        transaction.day = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: date)
        let components = Calendar.current.dateComponents([.month, .year], from: date)
        transaction.month = Calendar.current.date(from: components)
        transaction.recurringType = 0
        transaction.recurringCoefficient = 0
        transaction.onceRecurring = false
    }
}

enum TransactionTypeMigrationError: LocalizedError {
    case saveFailed(Error)
    case verificationFailed(Int)

    var errorDescription: String? {
        switch self {
        case let .saveFailed(error): return "Impossibile salvare la migrazione dei tipi di movimento: \(error.localizedDescription)"
        case let .verificationFailed(count): return "Migrazione dei tipi di movimento incompleta: \(count) movimenti senza tipo."
        }
    }
}

struct TransactionTypeMigrationHooks {
    var save: ((NSManagedObjectContext) throws -> Void)?
    static let production = TransactionTypeMigrationHooks(save: nil)
}

enum TransactionTypeMigrationService {
    static let markerKey = "transactionTypeMigrationV1Complete"

    static func migrateIfNeeded(in context: NSManagedObjectContext, defaults: UserDefaults, hooks: TransactionTypeMigrationHooks = .production) throws {
        guard !defaults.bool(forKey: markerKey) else { return }
        try context.performAndWait {
            let request = Transaction.fetchRequest()
            let transactions = try context.fetch(request)
            transactions.filter { $0.typeRawValue == nil }.forEach { transaction in
                transaction.typeRawValue = transaction.income ? TransactionType.income.rawValue : TransactionType.expense.rawValue
            }
            do {
                if let save = hooks.save { try save(context) } else { try context.save() }
            } catch {
                context.rollback()
                throw TransactionTypeMigrationError.saveFailed(error)
            }
            let remaining = try context.fetch(request).filter { $0.typeRawValue == nil }.count
            guard remaining == 0 else { throw TransactionTypeMigrationError.verificationFailed(remaining) }
        }
        defaults.set(true, forKey: markerKey)
    }
}

extension Transaction {
    var wrappedType: TransactionType {
        get {
            if let raw = typeRawValue, let type = TransactionType(rawValue: raw) { return type }
            return income ? .income : .expense
        }
        set {
            typeRawValue = newValue.rawValue
            income = newValue == .income
        }
    }

    var isTransfer: Bool { wrappedType == .transfer }
}

enum TransactionTotalsService {
    static func expenseTotal(_ transactions: some Sequence<Transaction>) -> Double {
        transactions.reduce(0) { $1.wrappedType == .expense ? $0 + $1.amount : $0 }
    }

    static func incomeTotal(_ transactions: some Sequence<Transaction>) -> Double {
        transactions.reduce(0) { $1.wrappedType == .income ? $0 + $1.amount : $0 }
    }

    static func categoryTotal(_ category: Category, transactions: some Sequence<Transaction>) -> Double {
        transactions.reduce(0) { total, transaction in
            total + (transaction.wrappedType == .expense && transaction.category == category ? transaction.amount : 0)
        }
    }
}

enum TransactionSearchService {
    static func matches(_ transaction: Transaction, query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !normalizedQuery.isEmpty else { return true }
        return [
            transaction.note ?? "",
            transaction.account?.name ?? "",
            transaction.destinationAccount?.name ?? ""
        ].contains { $0.localizedLowercase.contains(normalizedQuery) }
    }
}
