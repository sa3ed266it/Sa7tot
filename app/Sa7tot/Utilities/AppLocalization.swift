import Foundation
import SwiftUI

enum AppLocalization {
    static func key(_ key: String) -> LocalizedStringKey {
        LocalizedStringKey(key)
    }

    static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    static func format(_ key: String, _ value: CVarArg) -> String {
        String.localizedStringWithFormat(string(key), value)
    }

    static func format(_ key: String, _ first: CVarArg, _ second: CVarArg) -> String {
        String.localizedStringWithFormat(string(key), first, second)
    }

    static func format(_ key: String, _ first: CVarArg, _ second: CVarArg, _ third: CVarArg) -> String {
        String.localizedStringWithFormat(string(key), first, second, third)
    }

}

enum FinancialFormatting {
    static func currency(
        minorUnits: Int64,
        currencyCode: String,
        exponent: Int,
        showCents: Bool = true,
        locale: Locale = .current
    ) -> String {
        let number = NSDecimalNumber(
            mantissa: UInt64(abs(minorUnits)),
            exponent: Int16(-exponent),
            isNegative: minorUnits < 0
        )
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = showCents ? exponent : 0
        formatter.minimumFractionDigits = showCents ? exponent : 0
        return formatter.string(from: number) ?? "(minor)"
    }

    static func digits(
        minorUnits: Int64,
        currencyCode: String,
        exponent: Int,
        showCents: Bool = true,
        locale: Locale = .current
    ) -> String {
        let number = NSDecimalNumber(
            mantissa: UInt64(abs(minorUnits)),
            exponent: Int16(-exponent),
            isNegative: false
        )
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = showCents ? exponent : 0
        formatter.minimumFractionDigits = showCents ? exponent : 0
        return formatter.string(from: number) ?? "0"
    }

    static func date(_ date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func time(_ date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
