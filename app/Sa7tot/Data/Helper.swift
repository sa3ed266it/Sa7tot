//
//  Helper.swift
//  sa7tot
//
//  Created by Rafael Soh on 13/8/22.
//

import Foundation

enum Sa7totSharedIconPresentation {
    static func symbol(for name: String, storedValue: String) -> String {
        if storedValue.hasPrefix("sf:") {
            return String(storedValue.dropFirst(3))
        }

        return CategoryIconRegistry.symbol(for: name)
    }
}

/// Shared, Foundation-only source of truth for category symbols.
/// The app and widget targets both use this registry.
enum CategoryIconRegistry {
    private static let symbols: [String: String] = [
        "trasporti": "tram.fill", "transport": "tram.fill",
        "affitto": "house.fill", "rent": "house.fill", "casa": "house.fill",
        "abbonamento": "arrow.triangle.2.circlepath", "abbonamenti": "arrow.triangle.2.circlepath", "subscriptions": "arrow.triangle.2.circlepath",
        "spesa": "cart.fill", "spese": "cart.fill", "groceries": "cart.fill",
        "famiglia": "person.2.fill", "family": "person.2.fill",
        "utenza": "lightbulb.fill", "utenze": "lightbulb.fill", "bolletta": "lightbulb.fill", "bollette": "lightbulb.fill", "utilities": "lightbulb.fill",
        "moda": "tshirt.fill", "fashion": "tshirt.fill", "shopping": "tshirt.fill",
        "salute": "cross.case.fill", "healthcare": "cross.case.fill",
        "animali": "pawprint.fill", "animale": "pawprint.fill", "pets": "pawprint.fill",
        "cibo": "fork.knife", "food": "fork.knife",
        "regalo": "gift.fill", "regali": "gift.fill", "gift": "gift.fill", "gifts": "gift.fill",
        "stipendio": "banknote.fill", "entrata": "banknote.fill", "entrate": "banknote.fill", "reddito": "banknote.fill", "paycheck": "banknote.fill", "salary": "banknote.fill",
        "bonus": "sparkles", "extra": "sparkles", "tips": "sparkles",
        "rimborso": "arrow.uturn.backward.circle.fill", "refund": "arrow.uturn.backward.circle.fill",
        "vendite": "bag.fill", "vendita": "bag.fill", "sales": "bag.fill",
        "intrattenimento": "gamecontroller.fill", "svago": "gamecontroller.fill", "entertainment": "gamecontroller.fill",
        "viaggio": "airplane", "viaggi": "airplane", "travel": "airplane",
        "istruzione": "book.fill", "education": "book.fill",
        "sport": "figure.run",
        "risparmi": "building.columns.fill", "savings": "building.columns.fill",
        "altro": "tag.fill", "other": "tag.fill",
        "allowance": "banknote.fill", "part time": "briefcase.fill", "investments": "chart.bar.fill",
        "sneakers": "shoe.2.fill"
    ]

    static func normalized(_ name: String) -> String {
        name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func symbol(for name: String) -> String {
        symbols[normalized(name)] ?? "tag.fill"
    }
}

extension Transaction {
    var wrappedAmount: Double {
        amount
    }

    var wrappedDate: Date {
        date ?? Date.now
    }

    var wrappedNote: String {
        note ?? ""
    }

    var wrappedCategoryName: String {
        category?.wrappedName ?? ""
    }

    var wrappedColour: String {
        category?.wrappedColour ?? ""
    }

    var nextTransactionDate: Date {
        if recurringType == 1 {
            return Calendar.current.date(byAdding: .day, value: Int(recurringCoefficient), to: day ?? Date.now)!
        } else if recurringType == 2 {
            return Calendar.current.date(byAdding: .day, value: Int(recurringCoefficient * 7), to: day ?? Date.now)!
        } else if recurringType == 3 {
            return Calendar.current.date(byAdding: .month, value: Int(recurringCoefficient), to: day ?? Date.now)!
        }

        return date ?? Date.now
    }
}

extension TemplateTransaction {
    var wrappedAmount: Double {
        amount
    }

    var wrappedNote: String {
        note ?? ""
    }

    var wrappedEmoji: String {
        category?.wrappedEmoji ?? ""
    }

    var wrappedColour: String {
        category?.wrappedColour ?? ""
    }
}

extension Category {
    var wrappedColour: String {
        colour ?? "#FFFFFF"
    }

    var wrappedEmoji: String {
        emoji ?? "😄️"
    }

    var iconSymbol: String {
        Sa7totSharedIconPresentation.symbol(for: wrappedName, storedValue: emoji ?? "")
    }

    var wrappedName: String {
        name ?? ""
    }

    var wrappedDate: Date {
        dateCreated ?? Date.now
    }

    var fullName: String {
        wrappedEmoji + "  " + wrappedName
    }

    var allTransactions: [Transaction] {
        let set = transactions as? Set<Transaction> ?? []
        return set.sorted {
            $0.wrappedDate < $1.wrappedDate
        }
    }

    var transactionCount: Int {
        transactions?.count ?? 0
    }
}

public extension Budget {
    var wrappedColour: String {
        category?.wrappedColour ?? "#FFFFFF"
    }

    var wrappedName: String {
        category?.wrappedName ?? ""
    }

    var wrappedEmoji: String {
        category?.wrappedEmoji ?? ""
    }

    var fullName: String {
        return wrappedEmoji + " " + wrappedName
    }

    var wrappedDate: Date {
        return startDate ?? Date.now
    }

    var endDate: Date {
        if type == 1 {
            return Calendar.current.date(byAdding: .day, value: 1, to: startDate ?? Date.now)!
        } else if type == 2 {
            return Calendar.current.date(byAdding: .day, value: 7, to: startDate ?? Date.now)!
        } else if type == 3 {
            return Calendar.current.date(byAdding: .month, value: 1, to: startDate ?? Date.now)!
        } else if type == 4 {
            return Calendar.current.date(byAdding: .year, value: 1, to: startDate ?? Date.now)!
        }
        return startDate ?? Date.now
    }
}

public extension MainBudget {
    var wrappedDate: Date {
        return startDate ?? Date.now
    }

    var endDate: Date {
        if type == 1 {
            return Calendar.current.date(byAdding: .day, value: 1, to: startDate ?? Date.now)!
        } else if type == 2 {
            return Calendar.current.date(byAdding: .day, value: 7, to: startDate ?? Date.now)!
        } else if type == 3 {
            return Calendar.current.date(byAdding: .month, value: 1, to: startDate ?? Date.now)!
        } else if type == 4 {
            return Calendar.current.date(byAdding: .year, value: 1, to: startDate ?? Date.now)!
        }

        return startDate ?? Date.now
    }
}
