//
//  CalendarSettingsSupport.swift
//  Sa7tot
//

import Foundation

enum Sa7totWeekday: Int, CaseIterable, Identifiable {
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    case sunday = 1

    var id: Int { rawValue }

    var localizedName: String {
        switch self {
        case .monday: return AppLocalization.string("weekday.monday")
        case .tuesday: return AppLocalization.string("weekday.tuesday")
        case .wednesday: return AppLocalization.string("weekday.wednesday")
        case .thursday: return AppLocalization.string("weekday.thursday")
        case .friday: return AppLocalization.string("weekday.friday")
        case .saturday: return AppLocalization.string("weekday.saturday")
        case .sunday: return AppLocalization.string("weekday.sunday")
        }
    }

    var italianName: String { localizedName }

    static var storedSelection: Sa7totWeekday {
        let value = UserDefaults(suiteName: "group.com.saied.sa7tot")?.integer(forKey: "firstWeekday") ?? 1
        return Sa7totWeekday(rawValue: (1...7).contains(value) ? value : 1) ?? .sunday
    }
}

enum Sa7totCalendarSettings {
    static let settingsDidChange = Notification.Name("Sa7totCalendarSettingsDidChange")

    static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale.current
        calendar.timeZone = Calendar.current.timeZone
        calendar.firstWeekday = Sa7totWeekday.storedSelection.rawValue
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func startOfMonth(for date: Date, calendar: Calendar = Calendar.current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func startOfNextMonth(for date: Date, calendar: Calendar = Calendar.current) -> Date {
        let start = startOfMonth(for: date, calendar: calendar)
        return calendar.date(byAdding: .month, value: 1, to: start) ?? start
    }

    static func startOfWeek(for date: Date, calendar: Calendar = Sa7totCalendarSettings.calendar()) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func updateWeekday(_ weekday: Sa7totWeekday) {
        UserDefaults(suiteName: "group.com.saied.sa7tot")?.set(weekday.rawValue, forKey: "firstWeekday")
        NotificationCenter.default.post(name: settingsDidChange, object: nil)
    }
}
