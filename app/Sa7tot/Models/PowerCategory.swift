//
//  PowerCategory.swift
//  Bonsai
//
//  Created by Rafael Soh on 6/6/22.
//

import Foundation
import SwiftUI

struct PowerCategory: Hashable, Identifiable {
    let id: UUID
    let category: Category
    let percent: Double
    let amount: Double
}

struct SuggestedCategory: Hashable, Identifiable {
    let canonicalKey: String
    let name: String
    var id: String { canonicalKey }
    var symbolName: String { CategoryIconRegistry.symbol(for: name) }

    static var expenses: [SuggestedCategory] {
        var holding = [SuggestedCategory]()
        let food = SuggestedCategory(canonicalKey: "expense.food", name: "Food")
        holding.append(food)

        let transport = SuggestedCategory(canonicalKey: "expense.transport", name: "Transport")
        holding.append(transport)

        let housing = SuggestedCategory(canonicalKey: "expense.rent", name: "Rent")
        holding.append(housing)

        let subscriptions = SuggestedCategory(canonicalKey: "expense.subscriptions", name: "Subscriptions")
        holding.append(subscriptions)

        let groceries = SuggestedCategory(canonicalKey: "expense.groceries", name: "Groceries")
        holding.append(groceries)

        let family = SuggestedCategory(canonicalKey: "expense.family", name: "Family")
        holding.append(family)

        let utilities = SuggestedCategory(canonicalKey: "expense.utilities", name: "Utilities")
        holding.append(utilities)

        let fashion = SuggestedCategory(canonicalKey: "expense.fashion", name: "Fashion")
        holding.append(fashion)

        let healthcare = SuggestedCategory(canonicalKey: "expense.healthcare", name: "Healthcare")
        holding.append(healthcare)

        let pets = SuggestedCategory(canonicalKey: "expense.pets", name: "Pets")
        holding.append(pets)

        let sneakers = SuggestedCategory(canonicalKey: "expense.sneakers", name: "Sneakers")
        holding.append(sneakers)

        let gifts = SuggestedCategory(canonicalKey: "expense.gifts", name: "Gifts")
        holding.append(gifts)

        return holding
    }

    static var incomes: [SuggestedCategory] {
        var holding = [SuggestedCategory]()
        let paycheck = SuggestedCategory(canonicalKey: "income.paycheck", name: "Paycheck")
        holding.append(paycheck)

        let allowance = SuggestedCategory(canonicalKey: "income.allowance", name: "Allowance")
        holding.append(allowance)

        let parttime = SuggestedCategory(canonicalKey: "income.part-time", name: "Part-Time")
        holding.append(parttime)

        let investments = SuggestedCategory(canonicalKey: "income.investments", name: "Investments")
        holding.append(investments)

        let gifts = SuggestedCategory(canonicalKey: "income.gifts", name: "Gifts")
        holding.append(gifts)

        let tips = SuggestedCategory(canonicalKey: "income.tips", name: "Tips")
        holding.append(tips)

        return holding
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
