//
//  GetInsightsIntent.swift
//  sa7tot
//
//  Created by Rafael Soh on 5/8/23.
//

import AppIntents
import Foundation
import SwiftUI

@available(iOS 16.4, *)
struct GetInsightsIntent: AppIntent {
    static var title: LocalizedStringResource = "Mostra statistiche"

    static var description =
        IntentDescription("Mostra le tue spese o entrate totali per un periodo specifico")

    @Parameter(title: "Tipo", description: "Tipo di dati", requestValueDialog: IntentDialog("Quale dei seguenti dati vuoi visualizzare?"))
    var type: ShortcutsInsightsType

    @Parameter(title: "Periodo", description: "Periodo dei dati", requestValueDialog: IntentDialog("Quale periodo vuoi considerare?"))
    var timeframe: ShortcutsInsightsTimeFrame

    @Parameter(title: "Filtri categoria", description: "Filtri categoria aggiuntivi", requestValueDialog: IntentDialog("Quali filtri categoria aggiuntivi vuoi applicare?"))
    var incomeCategories: [IncomeCategoryEntity]?

    @Parameter(title: "Filtri categoria", description: "Filtri categoria aggiuntivi", requestValueDialog: IntentDialog("Quali filtri categoria aggiuntivi vuoi applicare?"))
    var expenseCategories: [ExpenseCategoryEntity]?

    @MainActor
    func perform() async throws -> some ReturnsValue<Double> & ShowsSnippetView & ProvidesDialog {
        let dataController = DataController.shared
//        let dataController = DataController()

        let categories: [Category]
        let optionalIncome: Bool?
        let typeInt: Int

        switch type {
        case .net:
            categories = []
            optionalIncome = nil
            typeInt = 1
        case .income:
            if let unwrappedCategories = incomeCategories {
                categories = unwrappedCategories.compactMap { category in
                    try? dataController.findCategory(withId: category.id)
                }
            } else {
                categories = []
            }

            optionalIncome = true
            typeInt = 2
        case .spent:
            if let unwrappedCategories = expenseCategories {
                categories = unwrappedCategories.compactMap { category in
                    try? dataController.findCategory(withId: category.id)
                }
            } else {
                categories = []
            }
            optionalIncome = false
            typeInt = 3
        }

        let result = dataController.getShortcutInsights(type: typeInt, timeframe: timeframe.rawValue, optionalIncome: optionalIncome, categories: categories)

        return .result(value: result, dialog: "Ecco qui!") {
            ShortcutInsightsView(amount: result, type: type, timeframe: timeframe)
        }
    }

    static var parameterSummary: some ParameterSummary {
        Switch(\GetInsightsIntent.$type) {
            Case(ShortcutsInsightsType.net) {
                Summary("Calculate \(\.$type) for \(\.$timeframe)")
            }
            Case(ShortcutsInsightsType.income) {
                Summary("Calculate \(\.$type) for \(\.$timeframe)") {
                    \.$incomeCategories
                }
            }
            Case(ShortcutsInsightsType.spent) {
                Summary("Calculate \(\.$type) for \(\.$timeframe)") {
                    \.$expenseCategories
                }
            }
            DefaultCase {
                Summary("Calculate \(\.$type) for \(\.$timeframe)")
            }
        }
    }
}

enum ShortcutsInsightsTimeFrame: Int {
    case day = 1
    case week = 2
    case month = 3
    case year = 4
    case all = 5
}

@available(iOS 16, *)
extension ShortcutsInsightsTimeFrame: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Periodo")
    }

    static var caseDisplayRepresentations: [ShortcutsInsightsTimeFrame: DisplayRepresentation] = [
        .day: DisplayRepresentation(title: "oggi"),
        .week: DisplayRepresentation(title: "questa settimana"),
        .month: DisplayRepresentation(title: "questo mese"),
        .year: DisplayRepresentation(title: "quest’anno"),
        .all: DisplayRepresentation(title: "tutto il periodo")
    ]
}

enum ShortcutsInsightsType: String {
    case net, income, spent
}

@available(iOS 16, *)
extension ShortcutsInsightsType: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Tipo di statistiche")
    }

    static var caseDisplayRepresentations: [ShortcutsInsightsType: DisplayRepresentation] = [
        .net: DisplayRepresentation(title: "saldo totale"),
        .income: DisplayRepresentation(title: "entrate totali"),
        .spent: DisplayRepresentation(title: "spesa totale")
    ]
}

struct ShortcutInsightsView: View {
    let amount: Double
    let type: ShortcutsInsightsType
    let timeframe: ShortcutsInsightsTimeFrame

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!

    var leftText: String {
        switch type {
        case .net:
            return "Saldo totale"
        case .income:
            return "Entrate"
        case .spent:
            return "Speso"
        }
    }

    var rightText: String {
        switch timeframe {
        case .day:
            return "oggi"
        case .week:
            return "questa settimana"
        case .month:
            return "questo mese"
        case .year:
            return "quest’anno"
        case .all:
            return "tutto il periodo"
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

        return numberFormatter.string(from: NSNumber(value: amount)) ?? "$0"
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(leftText + " " + rightText)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(Color.SubtitleText)

            Text(amountString)
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .padding(20)
    }
}
