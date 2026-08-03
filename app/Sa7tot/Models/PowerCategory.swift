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

struct SuggestedCategory: Hashable {
    let name: String
    var symbolName: String { CategoryIconRegistry.symbol(for: name) }

    static var expenses: [SuggestedCategory] {
        var holding = [SuggestedCategory]()
        let food = SuggestedCategory(name: "Food")
        holding.append(food)

        let transport = SuggestedCategory(name: "Transport")
        holding.append(transport)

        let housing = SuggestedCategory(name: "Rent")
        holding.append(housing)

        let subscriptions = SuggestedCategory(name: "Subscriptions")
        holding.append(subscriptions)

        let groceries = SuggestedCategory(name: "Groceries")
        holding.append(groceries)

        let family = SuggestedCategory(name: "Family")
        holding.append(family)

        let utilities = SuggestedCategory(name: "Utilities")
        holding.append(utilities)

        let fashion = SuggestedCategory(name: "Fashion")
        holding.append(fashion)

        let healthcare = SuggestedCategory(name: "Healthcare")
        holding.append(healthcare)

        let pets = SuggestedCategory(name: "Pets")
        holding.append(pets)

        let sneakers = SuggestedCategory(name: "Sneakers")
        holding.append(sneakers)

        let gifts = SuggestedCategory(name: "Gifts")
        holding.append(gifts)

        return holding
    }

    static var incomes: [SuggestedCategory] {
        var holding = [SuggestedCategory]()
        let paycheck = SuggestedCategory(name: "Paycheck")
        holding.append(paycheck)

        let allowance = SuggestedCategory(name: "Allowance")
        holding.append(allowance)

        let parttime = SuggestedCategory(name: "Part-Time")
        holding.append(parttime)

        let investments = SuggestedCategory(name: "Investments")
        holding.append(investments)

        let gifts = SuggestedCategory(name: "Gifts")
        holding.append(gifts)

        let tips = SuggestedCategory(name: "Tips")
        holding.append(tips)

        return holding
    }
}
