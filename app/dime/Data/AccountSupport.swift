import CoreData
import Foundation

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

            if let existing = accounts.first(where: { $0.name == defaultAccountName }) {
                account = existing
            } else if let existing = accounts.first(where: { !$0.isArchived }) {
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
        request.predicate = NSPredicate(format: "isArchived = NO")
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
        var incomeTotal = 0.0
        var expenseTotal = 0.0
        for transaction in transactions {
            guard transaction.account == account else { continue }
            if transaction.income {
                incomeTotal += transaction.amount
            } else {
                expenseTotal += transaction.amount
            }
        }
        return balance(openingBalance: account.openingBalance, type: account.wrappedType, income: incomeTotal, expenses: expenseTotal)
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
}
