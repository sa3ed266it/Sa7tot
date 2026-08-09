import Foundation

enum SubscriptionStatus: Int16, CaseIterable {
    case active = 0
    case paused = 1
    case cancelled = 2
}

enum SubscriptionCadence: Int16, CaseIterable {
    case weekly = 0
    case monthly = 1
    case yearly = 2
}

enum SubscriptionDisplayIdentity {
    static func name(customName: String?, serviceID: String?) -> String {
        if let customName = normalized(customName) { return customName }
        if let serviceID = normalized(serviceID) { return serviceID }
        return "Abbonamento"
    }

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

enum SubscriptionScheduleCalculator {
    private static let maximumOccurrenceIndex = 100_000

    static func nextOccurrence(
        after date: Date,
        anchor: Date,
        cadence: SubscriptionCadence,
        interval: Int,
        calendar: Calendar = .current
    ) -> Date? {
        guard interval >= 1 else { return nil }
        guard let candidate = firstOccurrence(
            onOrAfter: date,
            anchor: anchor,
            cadence: cadence,
            interval: interval,
            calendar: calendar
        ) else { return nil }

        if candidate > date { return candidate }
        return occurrence(
            at: estimatedIndex(for: date, anchor: anchor, cadence: cadence, interval: interval, calendar: calendar) + 1,
            anchor: anchor,
            cadence: cadence,
            interval: interval,
            calendar: calendar
        )
    }

    static func firstOccurrence(
        onOrAfter date: Date,
        anchor: Date,
        cadence: SubscriptionCadence,
        interval: Int,
        calendar: Calendar = .current
    ) -> Date? {
        guard interval >= 1 else { return nil }
        if date <= anchor { return anchor }

        var index = max(0, estimatedIndex(for: date, anchor: anchor, cadence: cadence, interval: interval, calendar: calendar))
        guard var current = occurrence(
            at: index,
            anchor: anchor,
            cadence: cadence,
            interval: interval,
            calendar: calendar
        ) else { return nil }

        while current < date {
            index += 1
            guard index < maximumOccurrenceIndex,
                  let next = occurrence(
                      at: index,
                      anchor: anchor,
                      cadence: cadence,
                      interval: interval,
                      calendar: calendar
                  ) else { return nil }
            current = next
        }

        while index > 0,
              let previous = occurrence(
                  at: index - 1,
                  anchor: anchor,
                  cadence: cadence,
                  interval: interval,
                  calendar: calendar
              ), previous >= date {
            index -= 1
            current = previous
        }

        return current
    }

    static func occurrences(
        onOrAfter startDate: Date,
        through endDate: Date,
        anchor: Date,
        cadence: SubscriptionCadence,
        interval: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard interval >= 1, startDate <= endDate else { return [] }
        guard var current = firstOccurrence(
            onOrAfter: startDate,
            anchor: anchor,
            cadence: cadence,
            interval: interval,
            calendar: calendar
        ) else { return [] }

        var result: [Date] = []
        var index = estimatedIndex(for: current, anchor: anchor, cadence: cadence, interval: interval, calendar: calendar)
        while current <= endDate, index < maximumOccurrenceIndex {
            result.append(current)
            index += 1
            guard let next = occurrence(
                at: index,
                anchor: anchor,
                cadence: cadence,
                interval: interval,
                calendar: calendar
            ) else { break }
            current = next
        }
        return result
    }

    private static func occurrence(
        at index: Int,
        anchor: Date,
        cadence: SubscriptionCadence,
        interval: Int,
        calendar: Calendar
    ) -> Date? {
        guard index >= 0, index < maximumOccurrenceIndex else { return nil }
        let value = index * interval

        switch cadence {
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: value, to: anchor)
        case .monthly:
            return monthOccurrence(offset: value, anchor: anchor, calendar: calendar)
        case .yearly:
            return yearOccurrence(offset: value, anchor: anchor, calendar: calendar)
        }
    }

    private static func monthOccurrence(offset: Int, anchor: Date, calendar: Calendar) -> Date? {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: anchor)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }

        let monthIndex = year * 12 + (month - 1) + offset
        let targetYear = monthIndex / 12
        let targetMonth = monthIndex % 12 + 1
        var target = DateComponents()
        target.year = targetYear
        target.month = targetMonth
        target.day = min(day, daysInMonth(year: targetYear, month: targetMonth, calendar: calendar))
        target.hour = components.hour
        target.minute = components.minute
        target.second = components.second
        target.nanosecond = components.nanosecond
        return calendar.date(from: target)
    }

    private static func yearOccurrence(offset: Int, anchor: Date, calendar: Calendar) -> Date? {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: anchor)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }

        let targetYear = year + offset
        var target = DateComponents()
        target.year = targetYear
        target.month = month
        target.day = min(day, daysInMonth(year: targetYear, month: month, calendar: calendar))
        target.hour = components.hour
        target.minute = components.minute
        target.second = components.second
        target.nanosecond = components.nanosecond
        return calendar.date(from: target)
    }

    private static func daysInMonth(year: Int, month: Int, calendar: Calendar) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else { return 28 }
        return range.count
    }

    private static func estimatedIndex(
        for date: Date,
        anchor: Date,
        cadence: SubscriptionCadence,
        interval: Int,
        calendar: Calendar
    ) -> Int {
        guard date > anchor else { return 0 }
        switch cadence {
        case .weekly:
            let days = max(0, calendar.dateComponents([.day], from: anchor, to: date).day ?? 0)
            return max(0, days / (7 * interval))
        case .monthly:
            let start = calendar.dateComponents([.year, .month], from: anchor)
            let end = calendar.dateComponents([.year, .month], from: date)
            let months = max(0, ((end.year ?? 0) - (start.year ?? 0)) * 12 + (end.month ?? 0) - (start.month ?? 0))
            return max(0, months / interval)
        case .yearly:
            let start = calendar.component(.year, from: anchor)
            let end = calendar.component(.year, from: date)
            return max(0, (end - start) / interval)
        }
    }
}
