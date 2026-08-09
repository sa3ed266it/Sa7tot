import Foundation

enum BudgetAmountParser {
    static func decimal(from text: String) -> Decimal? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.number(from: value)?.decimalValue
    }

    static func isValid(_ amount: Decimal) -> Bool {
        amount > 0 && NSDecimalNumber(decimal: amount).doubleValue.isFinite
    }
}
