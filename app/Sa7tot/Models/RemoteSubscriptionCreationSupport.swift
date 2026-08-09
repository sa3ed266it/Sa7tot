import Foundation

enum AddEntryMode: String, CaseIterable, Identifiable {
    case expense
    case income
    case subscription

    var id: String { rawValue }
}

enum SubscriptionDateNormalization {
    static func localNoon(_ date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var normalized = DateComponents()
        normalized.year = components.year
        normalized.month = components.month
        normalized.day = components.day
        normalized.hour = 12
        normalized.minute = 0
        normalized.second = 0
        normalized.nanosecond = 0
        return calendar.date(from: normalized) ?? date
    }

    static func nextRenewal(
        cadence: SubscriptionCadence,
        startDate: Date,
        from today: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let anchor = localNoon(startDate, calendar: calendar)
        let todayAnchor = localNoon(today, calendar: calendar)
        let anchorDay = calendar.startOfDay(for: anchor)
        let todayDay = calendar.startOfDay(for: todayAnchor)

        if anchorDay > todayDay {
            return SubscriptionScheduleCalculator.firstOccurrence(
                onOrAfter: anchor,
                anchor: anchor,
                cadence: cadence,
                interval: 1,
                calendar: calendar
            ) ?? anchor
        }

        return SubscriptionScheduleCalculator.nextOccurrence(
            after: todayAnchor,
            anchor: anchor,
            cadence: cadence,
            interval: 1,
            calendar: calendar
        ) ?? anchor
    }

    static func firstScheduledOccurrence(
        cadence: SubscriptionCadence,
        startDate: Date,
        from now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let anchor = localNoon(startDate, calendar: calendar)
        let todayAnchor = localNoon(now, calendar: calendar)
        let firstDate = max(anchor, todayAnchor)

        return SubscriptionScheduleCalculator.firstOccurrence(
            onOrAfter: firstDate,
            anchor: anchor,
            cadence: cadence,
            interval: 1,
            calendar: calendar
        ) ?? firstDate
    }
}
