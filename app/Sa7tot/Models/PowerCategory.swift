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
    let symbolName: String

    static var expenses: [SuggestedCategory] {
        var holding = [SuggestedCategory]()
        let food = SuggestedCategory(name: "Food", symbolName: "fork.knife")
        holding.append(food)

        let transport = SuggestedCategory(name: "Transport", symbolName: "tram.fill")
        holding.append(transport)

        let housing = SuggestedCategory(name: "Rent", symbolName: "house.fill")
        holding.append(housing)

        let subscriptions = SuggestedCategory(name: "Subscriptions", symbolName: "repeat.circle.fill")
        holding.append(subscriptions)

        let groceries = SuggestedCategory(name: "Groceries", symbolName: "cart.fill")
        holding.append(groceries)

        let family = SuggestedCategory(name: "Family", symbolName: "person.2.fill")
        holding.append(family)

        let utilities = SuggestedCategory(name: "Utilities", symbolName: "lightbulb.fill")
        holding.append(utilities)

        let fashion = SuggestedCategory(name: "Fashion", symbolName: "tshirt.fill")
        holding.append(fashion)

        let healthcare = SuggestedCategory(name: "Healthcare", symbolName: "cross.case.fill")
        holding.append(healthcare)

        let pets = SuggestedCategory(name: "Pets", symbolName: "pawprint.fill")
        holding.append(pets)

        let sneakers = SuggestedCategory(name: "Sneakers", symbolName: "shoe.2.fill")
        holding.append(sneakers)

        let gifts = SuggestedCategory(name: "Gifts", symbolName: "gift.fill")
        holding.append(gifts)

        return holding
    }

    static var incomes: [SuggestedCategory] {
        var holding = [SuggestedCategory]()
        let paycheck = SuggestedCategory(name: "Paycheck", symbolName: "banknote.fill")
        holding.append(paycheck)

        let allowance = SuggestedCategory(name: "Allowance", symbolName: "wallet.pass.fill")
        holding.append(allowance)

        let parttime = SuggestedCategory(name: "Part-Time", symbolName: "briefcase.fill")
        holding.append(parttime)

        let investments = SuggestedCategory(name: "Investments", symbolName: "chart.bar.fill")
        holding.append(investments)

        let gifts = SuggestedCategory(name: "Gifts", symbolName: "gift.fill")
        holding.append(gifts)

        let tips = SuggestedCategory(name: "Tips", symbolName: "banknote.fill")
        holding.append(tips)

        return holding
    }
}
