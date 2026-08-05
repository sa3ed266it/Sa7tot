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
            SuggestedCategory(canonicalKey: "expense.food", name: "Food"),
            SuggestedCategory(canonicalKey: "expense.transport", name: "Transport"),
            SuggestedCategory(canonicalKey: "expense.rent", name: "Rent"),
            SuggestedCategory(canonicalKey: "expense.subscriptions", name: "Subscriptions"),
            SuggestedCategory(canonicalKey: "expense.groceries", name: "Groceries"),
            SuggestedCategory(canonicalKey: "expense.family", name: "Family"),
            SuggestedCategory(canonicalKey: "expense.utilities", name: "Utilities"),
            SuggestedCategory(canonicalKey: "expense.fashion", name: "Fashion"),
            SuggestedCategory(canonicalKey: "expense.healthcare", name: "Healthcare"),
            SuggestedCategory(canonicalKey: "expense.pets", name: "Pets"),
            SuggestedCategory(canonicalKey: "expense.sneakers", name: "Sneakers"),
            SuggestedCategory(canonicalKey: "expense.gifts", name: "Gifts")
        ]
    }

    static var incomes: [SuggestedCategory] {
        [
            SuggestedCategory(canonicalKey: "income.paycheck", name: "Paycheck"),
            SuggestedCategory(canonicalKey: "income.allowance", name: "Allowance"),
            SuggestedCategory(canonicalKey: "income.part-time", name: "Part-Time"),
            SuggestedCategory(canonicalKey: "income.investments", name: "Investments"),
            SuggestedCategory(canonicalKey: "income.gifts", name: "Gifts"),
            SuggestedCategory(canonicalKey: "income.tips", name: "Tips")
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
