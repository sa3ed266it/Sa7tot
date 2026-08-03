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
            return "Migrazione conti incompleta: attesi (expected) movimenti, trovati (actual)."
        case let .saveFailed(error): return "Impossibile salvare la migrazione dei conti: (error.localizedDescription)"
        }
    }
}

enum AccountMigrationService {
    static let markerKey = "accountsMigrationV1Complete"
    static let defaultAccountName = "Conto principale"

    static func migrateIfNeeded(in context: NSManagedObjectContext, currencyCode: String, defaults: UserDefaults) throws {
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
                try context.save()
            } catch {
                context.rollback()
                throw AccountMigrationError.saveFailed(error)
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

enum AccountBalanceService {
    static func balance(openingBalance: Double, type: AccountType, income: Double, expenses: Double) -> Double {
        openingBalance + income - expenses
    }

    static func balance(for account: Account, transactions: some Sequence<Transaction>) -> Double {
        let movementTotal = transactions.reduce(0) { result, transaction in
            guard transaction.account == account else { return result }
            if AccountType(rawValue: account.typeRawValue ?? "") == .creditCard {
                return result + (transaction.income ? transaction.amount : -transaction.amount)
            }
            return result + (transaction.income ? transaction.amount : -transaction.amount)
        }
        return balance(openingBalance: account.openingBalance, type: account.wrappedType, income: movementTotal > 0 ? movementTotal : 0, expenses: movementTotal < 0 ? -movementTotal : 0)
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
}
