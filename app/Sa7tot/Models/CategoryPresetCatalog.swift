import Foundation

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
        .init(key: "income.paycheck", income: true, titleKey: "category.preset.income.paycheck", symbolName: "arrow.down.circle.fill", defaultColor: "#35A77A", order: 0),
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
