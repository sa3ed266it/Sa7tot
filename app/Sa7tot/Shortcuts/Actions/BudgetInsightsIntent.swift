//
//  BudgetInsightsIntent.swift
//  sa7tot
//
//  Created by Rafael Soh on 6/8/23.
//

import AppIntents
import Foundation
import SwiftUI

@available(iOS 16.4, *)
struct BudgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Stato del budget"

    static var description =
        IntentDescription("Mostra l’importo rimanente di un budget specifico")

    @Parameter(title: "Tipo di budget", requestValueDialog: IntentDialog("Di quale tipo di budget vuoi visualizzare lo stato?"))
    var type: ShortcutsBudgetsType

    @Parameter(title: "Budget di categoria", requestValueDialog: IntentDialog("Seleziona un budget di categoria."))
    var budget: BudgetEntity?

    @MainActor
    func perform() async throws -> some ReturnsValue<Double> & ShowsSnippetView & ProvidesDialog {
        if type == .category && budget == nil {
            throw $budget.needsValueError()
        }

//        let dataController = DataController()

        let dataController = DataController.shared

        var amount: Double = 0
        var budgetType: Int16 = 0

        switch type {
        case .overall:
            if let mainBudget = dataController.results(for: dataController.fetchRequestForMainBudget()).first {
                amount = dataController.getBudgetLeftover(overallBudget: mainBudget)

                budgetType = mainBudget.type
            }
        case .category:
            if let unwrappedBudget = budget {
                let categoryBudget = try dataController.findBudget(withId: unwrappedBudget.id)

                amount = dataController.getBudgetLeftover(budget: categoryBudget)

                budgetType = categoryBudget.type
            }
        }

        return .result(value: amount, dialog: "Ecco qui!") {
            ShortcutBudgetView(amount: amount, type: Int(budgetType))
        }
    }

    static var parameterSummary: some ParameterSummary {
        Switch(\BudgetIntent.$type) {
            Case(ShortcutsBudgetsType.category) {
                Summary("Calcola l’importo rimanente per \(\.$budget) \(\.$type)")
            }
            Case(ShortcutsBudgetsType.overall) {
                Summary("Calcola l’importo rimanente per \(\.$type)")
            }
            DefaultCase {
                Summary("Calcola l’importo rimanente per \(\.$type)")
            }
        }
    }
}

enum ShortcutsBudgetsType: String {
    case overall, category
}

@available(iOS 16, *)
extension ShortcutsBudgetsType: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Tipo di budget")
    }

    static var caseDisplayRepresentations: [ShortcutsBudgetsType: DisplayRepresentation] = [
        .overall: DisplayRepresentation(title: "budget complessivo"),
        .category: DisplayRepresentation(title: "budget di categoria")
    ]
}

struct ShortcutBudgetView: View {
    let amount: Double
    let type: Int

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!

    var budgetType: String {
        switch type {
        case 1:
            return "oggi"
        case 2:
            return "questa settimana"
        case 3:
            return "questo mese"
        case 4:
            return "quest’anno"
        default:
            return "questa settimana"
        }
    }

    var amountString: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = currency

        if showCents {
            numberFormatter.maximumFractionDigits = 2
        } else {
            numberFormatter.maximumFractionDigits = 0
        }

        return numberFormatter.string(from: NSNumber(value: abs(amount))) ?? "$0"
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(amountString)
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .lineLimit(1)

            if amount > 0 {
                Text("restante \(budgetType)")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
            } else {
                Text("oltre \(budgetType)")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
            }
        }
        .padding(20)
    }
}
