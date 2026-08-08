//
//  NewTransactionIntent.swift
//  sa7tot
//
//  Created by Rafael Soh on 23/7/23.
//

import AppIntents
import Foundation
import SwiftUI

@available(iOS 16.4, *)
struct NewTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Nuovo movimento"

    static var description =
        IntentDescription("Registra nuovi movimenti in un attimo")

    @Parameter(title: "Tipo", description: "Tipo di movimento", requestValueDialog: IntentDialog("Vuoi registrare un’entrata o una spesa?"))
    var income: ShortcutTransactionType

    @Parameter(title: "Importo", description: "Valore del movimento", controlStyle: .field, inclusiveRange: (lowerBound: 0.01, upperBound: 100_000_000), requestValueDialog: IntentDialog("Qual è l’importo del movimento?"))
    var amount: Double

    @Parameter(title: "Categoria", description: "Categoria associata al movimento", requestValueDialog: IntentDialog("A quale categoria appartiene?"))
    var incomeCategory: IncomeCategoryEntity?

    @Parameter(title: "Categoria", description: "Categoria associata al movimento", requestValueDialog: IntentDialog("A quale categoria appartiene?"))
    var expenseCategory: ExpenseCategoryEntity?

    @Parameter(title: "Nota")
    var note: String?

    @Parameter(title: "Movimento ricorrente", default: false)
    var recurringTransaction: Bool

    @Parameter(title: "Frequenza di ripetizione", default: .weekly)
    var recurringType: RepeatType

//    struct CategoryOptionsProvider: DynamicOptionsProvider {
//
//        func results() async throws -> ItemCollection<CategoryEntity> {
//            let dataController = DataController()
//
//            }
//
//            let incomeCategories = categories.filter { $0.income }
//            let expenseCategories = categories.filter { !$0.income }
//
//            return ItemCollection {
//                ItemSection(
//                    "Income Categories",
//                    items: incomeCategories.map {
//                        IntentItem<CategoryEntity>.init($0)
//                    }
//                )
//                ItemSection(
//                    "Expense Categories",
//                    items: expenseCategories.map {
//                        IntentItem<CategoryEntity>.init($0)
//                    }
//                )
//
//            }
//        }
//    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        if expenseCategory == nil && incomeCategory == nil {
            if income == .expense {
                throw $expenseCategory.needsValueError()
            } else {
                throw $incomeCategory.needsValueError()
            }
        } else {
            if amount == 0 {
                throw $amount.needsValueError()
            }

            let dataController = DataController.shared
            let repeatType: Int

            if !recurringTransaction {
                repeatType = 0
            } else {
                switch recurringType {
                case .daily:
                    repeatType = 1
                case .weekly:
                    repeatType = 2
                case .monthly:
                    repeatType = 3
                }
            }

            if income == .expense {
                if let unwrappedExpenseCategory = expenseCategory {
                    let category = try dataController.findCategory(withId: unwrappedExpenseCategory.id)

                    let transaction = try dataController.newTransaction(note: note ?? "", category: category, income: false, amount: amount, date: Date.now, repeatType: repeatType, repeatCoefficient: 1, delay: false)

                    return .result(dialog: "Spesa registrata con successo.") {
                        ShortcutTransactionView(transaction: transaction)
                    }
                } else {
                    throw $expenseCategory.needsValueError()
                }
            } else {
                if let unwrappedIncomeCategory = incomeCategory {
                    let category = try dataController.findCategory(withId: unwrappedIncomeCategory.id)

                    let transaction = try dataController.newTransaction(note: note ?? "", category: category, income: true, amount: amount, date: Date.now, repeatType: repeatType, repeatCoefficient: 1, delay: false)

                    return .result(dialog: "Entrata registrata con successo.") {
                        ShortcutTransactionView(transaction: transaction)
                    }
                } else {
                    throw $incomeCategory.needsValueError()
                }
            }
        }
    }

    static var parameterSummary: some ParameterSummary {
        Switch(\NewTransactionIntent.$income) {
            Case(ShortcutTransactionType.expense) {
                When(\NewTransactionIntent.$recurringTransaction, .equalTo, true, {
                    Summary("Registra un’\(\.$income) di \(\.$amount) in \(\.$expenseCategory)") {
                        \.$note
                        \.$recurringTransaction
                        \.$recurringType
                    }
                }, otherwise: {
                    Summary("Registra un’\(\.$income) di \(\.$amount) in \(\.$expenseCategory)") {
                        \.$note
                        \.$recurringTransaction
                    }
                })
            }
            Case(ShortcutTransactionType.income) {
                When(\NewTransactionIntent.$recurringTransaction, .equalTo, true, {
                    Summary("Registra un’\(\.$income) di \(\.$amount) in \(\.$incomeCategory)") {
                        \.$note
                        \.$recurringTransaction
                        \.$recurringType
                    }
                }, otherwise: {
                    Summary("Registra un’\(\.$income) di \(\.$amount) in \(\.$incomeCategory)") {
                        \.$note
                        \.$recurringTransaction
                    }
                })
            }
            DefaultCase {
                Summary("Registra un’\(\.$income) di \(\.$amount)") {
                    \.$note
                }
            }
        }
    }
}

// income or expense

enum ShortcutTransactionType: String {
    case income, expense
}

@available(iOS 16, *)
extension ShortcutTransactionType: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Tipo")
    }

    static var caseDisplayRepresentations: [ShortcutTransactionType: DisplayRepresentation] = [
        .income: DisplayRepresentation(title: "entrata",
                                       image: .init(systemName: "plus.square.fill")),
        .expense: DisplayRepresentation(title: "spesa",
                                        image: .init(systemName: "minus.square.fill"))
    ]
}

enum RepeatType: String {
    case daily, weekly, monthly
}

@available(iOS 16, *)
extension RepeatType: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Frequenza")
    }

    static var caseDisplayRepresentations: [RepeatType: DisplayRepresentation] = [
        .daily: DisplayRepresentation(title: "Ogni giorno"),
        .weekly: DisplayRepresentation(title: "Ogni settimana"),
        .monthly: DisplayRepresentation(title: "Ogni mese")
    ]
}

struct ShortcutTransactionView: View {
    let transaction: Transaction

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!

    var transactionAmountString: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = currency

        if showCents {
            numberFormatter.maximumFractionDigits = 2
        } else {
            numberFormatter.maximumFractionDigits = 0
        }

        return numberFormatter.string(from: NSNumber(value: transaction.amount)) ?? "$0"
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryLogIconView(iconIdentifier: transaction.category?.iconIdentifier ?? "sf:tag.fill",
                         categoryName: transaction.category?.wrappedName,
                         colour: (transaction.category?.wrappedColour ?? ""), future: false)
                .frame(width: 35, height: 35, alignment: .center)
                .overlay(alignment: .bottomTrailing) {
                    if transaction.recurringType > 0 {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.DarkIcon)
                            .padding(3)
                            .background(Color.AppSecondarySurface, in: RoundedRectangle(cornerRadius: 6))
                            .offset(x: 5, y: 5)
                    }
                }

            VStack(alignment: .leading) {
                Text(transaction.wrappedNote)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)

                Text(transaction.wrappedDate, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
                    .lineLimit(1)
            }
            Spacer()
            if transaction.income {
                Text("+\(transactionAmountString)")
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundColor(Color.IncomeGreen)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .layoutPriority(1)
            } else {
                Text("-\(transactionAmountString)")
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundColor(Color.PrimaryText)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
    }
}

@available(iOS 16.4, *)
struct LogWalletExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Registra spesa da Wallet"
    static var description = IntentDescription("Registra in Sa7tot una spesa ricevuta da una transazione Apple Wallet.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Importo", description: "Importo ricevuto da Wallet come testo")
    var amount: String

    @Parameter(title: "Esercente", default: "")
    var merchant: String

    @Parameter(title: "Data")
    var date: Date?

    @Parameter(title: "Etichetta carta/conto Wallet", default: "")
    var walletAccountLabel: String

    @Parameter(title: "Nota", default: "")
    var note: String

    @Parameter(title: "Riferimento esterno", default: "")
    var externalReference: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try await DataController.shared.waitForStore()
            let transaction = try DataController.shared.newWalletExpense(
                amountRaw: amount,
                merchant: merchant,
                date: date,
                walletAccountLabel: walletAccountLabel,
                note: note,
                externalReference: externalReference
            )
            let formatted = NumberFormatter.localizedString(from: NSNumber(value: transaction.amount), number: .currency)
            if transaction.wrappedReviewStatus == .needsReview {
                return .result(dialog: "Spesa registrata, ma da controllare: \(formatted) da \(merchant.isEmpty ? "Wallet" : merchant).")
            }
            return .result(dialog: "Spesa registrata: \(formatted) da \(merchant.isEmpty ? "Wallet" : merchant).")
        } catch let error as LocalizedError {
            throw error
        } catch {
            throw WalletAutomationError.persistence
        }
    }
}
