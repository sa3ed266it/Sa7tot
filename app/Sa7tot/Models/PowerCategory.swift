//
//  PowerCategory.swift
//  Bonsai
//
//  Created by Rafael Soh on 6/6/22.
//

import Foundation
import SwiftUI

struct SuggestedCategory: Hashable, Identifiable {
    let canonicalKey: String
    let name: String
    var id: String { canonicalKey }
    var symbolName: String { CategoryIconRegistry.symbol(for: name) }

    static var expenses: [SuggestedCategory] {
        [
            SuggestedCategory(canonicalKey: "expense.food", name: "Cibo"),
            SuggestedCategory(canonicalKey: "expense.transport", name: "Trasporti"),
            SuggestedCategory(canonicalKey: "expense.rent", name: "Affitto"),
            SuggestedCategory(canonicalKey: "expense.subscriptions", name: "Abbonamenti"),
            SuggestedCategory(canonicalKey: "expense.groceries", name: "Spesa"),
            SuggestedCategory(canonicalKey: "expense.family", name: "Famiglia"),
            SuggestedCategory(canonicalKey: "expense.utilities", name: "Utenze"),
            SuggestedCategory(canonicalKey: "expense.fashion", name: "Moda"),
            SuggestedCategory(canonicalKey: "expense.healthcare", name: "Salute"),
            SuggestedCategory(canonicalKey: "expense.pets", name: "Animali"),
            SuggestedCategory(canonicalKey: "expense.sneakers", name: "Sneakers"),
            SuggestedCategory(canonicalKey: "expense.gifts", name: "Regali")
        ]
    }

    static var incomes: [SuggestedCategory] {
        [
            SuggestedCategory(canonicalKey: "income.paycheck", name: "Stipendio"),
            SuggestedCategory(canonicalKey: "income.allowance", name: "Paghetta"),
            SuggestedCategory(canonicalKey: "income.part-time", name: "Part-time"),
            SuggestedCategory(canonicalKey: "income.investments", name: "Investimenti"),
            SuggestedCategory(canonicalKey: "income.gifts", name: "Regali"),
            SuggestedCategory(canonicalKey: "income.tips", name: "Mance")
        ]
    }
}

enum CategoryCanonicalIdentity {
    static func key(for suggestion: SuggestedCategory) -> String {
        suggestion.canonicalKey
    }

    static func key(for category: Category) -> String {
        let source = category.income ? SuggestedCategory.incomes : SuggestedCategory.expenses
        let nameKey = CategoryNameNormalizer.key(category.wrappedName)

        if let suggestion = source.first(where: { suggestion in
            let localizedKey = CategoryNameNormalizer.key(NSLocalizedString(suggestion.name, comment: "category name"))
            return localizedKey == nameKey || CategoryNameNormalizer.key(suggestion.name) == nameKey
        }) {
            return suggestion.canonicalKey
        }

        let kind = category.income ? "income" : "expense"
        return "\(kind).custom.\(nameKey)"
    }
}
