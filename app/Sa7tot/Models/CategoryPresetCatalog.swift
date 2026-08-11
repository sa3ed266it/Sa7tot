import Foundation
import SwiftUI

struct CategoryPreset: Identifiable, Hashable, Sendable {
    let key: String
    let income: Bool
    let titleKey: String
    let symbolName: String
    let defaultColor: String
    let order: Int

    var id: String { key }
    var localizedTitle: String { AppLocalization.string(titleKey) }
}

enum CategoryPresetCatalog {
    static let expenses: [CategoryPreset] = [
        .init(key: "expense.food", income: false, titleKey: "category.preset.expense.food", symbolName: "fork.knife", defaultColor: "#279AF4", order: 0),
        .init(key: "expense.transport", income: false, titleKey: "category.preset.expense.transport", symbolName: "car.fill", defaultColor: "#61C7FA", order: 1),
        .init(key: "expense.rent", income: false, titleKey: "category.preset.expense.rent", symbolName: "house.fill", defaultColor: "#A6678A", order: 2),
        .init(key: "expense.groceries", income: false, titleKey: "category.preset.expense.groceries", symbolName: "cart.fill", defaultColor: "#5FAF9F", order: 3),
        .init(key: "expense.family", income: false, titleKey: "category.preset.expense.family", symbolName: "person.2.fill", defaultColor: "#ED80A2", order: 4),
        .init(key: "expense.utilities", income: false, titleKey: "category.preset.expense.utilities", symbolName: "bolt.fill", defaultColor: "#F6D24A", order: 5),
        .init(key: "expense.fashion", income: false, titleKey: "category.preset.expense.fashion", symbolName: "tshirt.fill", defaultColor: "#C56AF7", order: 6),
        .init(key: "expense.healthcare", income: false, titleKey: "category.preset.expense.healthcare", symbolName: "cross.case.fill", defaultColor: "#E34D63", order: 7),
        .init(key: "expense.pets", income: false, titleKey: "category.preset.expense.pets", symbolName: "pawprint.fill", defaultColor: "#84B4EB", order: 8),
        .init(key: "expense.sneakers", income: false, titleKey: "category.preset.expense.sneakers", symbolName: "shoe.2.fill", defaultColor: "#F3BF56", order: 9),
        .init(key: "expense.gifts", income: false, titleKey: "category.preset.expense.gifts", symbolName: "gift.fill", defaultColor: "#EC7A58", order: 10)
    ]

    static let incomes: [CategoryPreset] = [
        .init(key: "income.paycheck", income: true, titleKey: "category.preset.income.paycheck", symbolName: "creditcard.fill", defaultColor: "#35A77A", order: 0),
        .init(key: "income.allowance", income: true, titleKey: "category.preset.income.allowance", symbolName: "wallet.pass.fill", defaultColor: "#7CB0AA", order: 1),
        .init(key: "income.part_time", income: true, titleKey: "category.preset.income.part_time", symbolName: "briefcase.fill", defaultColor: "#6E7BF1", order: 2),
        .init(key: "income.investments", income: true, titleKey: "category.preset.income.investments", symbolName: "chart.line.uptrend.xyaxis", defaultColor: "#A0ACF9", order: 3),
        .init(key: "income.gifts", income: true, titleKey: "category.preset.income.gifts", symbolName: "gift.fill", defaultColor: "#F1AF8A", order: 4),
        .init(key: "income.tips", income: true, titleKey: "category.preset.income.tips", symbolName: "hand.thumbsup.fill", defaultColor: "#C38D5D", order: 5)
    ]

    static let all = expenses + incomes

    static func presets(income: Bool) -> [CategoryPreset] {
        income ? incomes : expenses
    }
}

public struct AccountCardGradientPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let primaryHex: String
    public let secondaryHex: String

    public init(id: String, displayName: String, primaryHex: String, secondaryHex: String) {
        self.id = id
        self.displayName = displayName
        self.primaryHex = primaryHex
        self.secondaryHex = secondaryHex
    }

    public var primaryColor: Color {
        hexToColor(primaryHex)
    }

    public var secondaryColor: Color {
        hexToColor(secondaryHex)
    }

    public var gradient: LinearGradient {
        LinearGradient(
            colors: [primaryColor, secondaryColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension AccountCardGradientPreset {
    public static let defaultPreset: AccountCardGradientPreset = all[2] // Royal Blue (#5E7CE2)

    public static let all: [AccountCardGradientPreset] = [
        AccountCardGradientPreset(id: "graphite", displayName: "Graphite", primaryHex: "#34363D", secondaryHex: "#111318"),
        AccountCardGradientPreset(id: "midnight", displayName: "Midnight", primaryHex: "#243B72", secondaryHex: "#10182E"),
        AccountCardGradientPreset(id: "royalBlue", displayName: "Royal Blue", primaryHex: "#5E7CE2", secondaryHex: "#3346A8"),
        AccountCardGradientPreset(id: "violet", displayName: "Violet", primaryHex: "#8A68F2", secondaryHex: "#5A35C8"),
        AccountCardGradientPreset(id: "emerald", displayName: "Emerald", primaryHex: "#19A77B", secondaryHex: "#087058"),
        AccountCardGradientPreset(id: "forest", displayName: "Forest", primaryHex: "#39785E", secondaryHex: "#1C4435"),
        AccountCardGradientPreset(id: "burgundy", displayName: "Burgundy", primaryHex: "#A44868", secondaryHex: "#5C2139"),
        AccountCardGradientPreset(id: "champagne", displayName: "Champagne", primaryHex: "#D6B46A", secondaryHex: "#9A7432")
    ]

    public static func match(hex: String?) -> AccountCardGradientPreset? {
        guard let hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return nil
        }
        let normalized = hex.hasPrefix("#") ? hex.uppercased() : "#\(hex.uppercased())"
        return all.first(where: { $0.primaryHex.uppercased() == normalized })
    }

    public static func gradient(forPrimaryHex hex: String?) -> LinearGradient {
        if let preset = match(hex: hex) {
            return preset.gradient
        }
        guard let hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hex.isEmpty,
              hex != "#FFFFFF",
              hex.caseInsensitiveCompare("FFFFFF") != .orderedSame else {
            return defaultPreset.gradient
        }
        let primaryColor = hexToColor(hex)
        let secondaryHex = darkenHex(hex, factor: 0.5)
        let secondaryColor = hexToColor(secondaryHex)
        return LinearGradient(
            colors: [primaryColor, secondaryColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func darkenHex(_ hex: String, factor: Double) -> String {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b: Double
        switch clean.count {
        case 6:
            (r, g, b) = (Double(int >> 16), Double(int >> 8 & 0xFF), Double(int & 0xFF))
        default:
            return "#111318"
        }
        let newR = max(0, min(255, Int(r * factor)))
        let newG = max(0, min(255, Int(g * factor)))
        let newB = max(0, min(255, Int(b * factor)))
        return String(format: "#%02X%02X%02X", newR, newG, newB)
    }
}

private func hexToColor(_ hex: String) -> Color {
    let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int = UInt64()
    Scanner(string: clean).scanHexInt64(&int)
    let r, g, b: Double
    switch clean.count {
    case 6:
        (r, g, b) = (Double(int >> 16), Double(int >> 8 & 0xFF), Double(int & 0xFF))
    default:
        (r, g, b) = (0, 0, 0)
    }
    return Color(.sRGB, red: r / 255.0, green: g / 255.0, blue: b / 255.0, opacity: 1.0)
}




