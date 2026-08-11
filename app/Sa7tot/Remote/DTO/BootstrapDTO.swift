import Foundation

public struct RemoteProfileDTO: Codable, Equatable, Sendable {
    public let userID: UUID
    public let locale: String?
    public let timezone: String
    public let defaultCurrencyCode: String
    public let monthStartDay: Int
    public let weekStartDay: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case locale
        case timezone
        case defaultCurrencyCode = "default_currency_code"
        case monthStartDay = "month_start_day"
        case weekStartDay = "week_start_day"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        locale = try container.decodeIfPresent(String.self, forKey: .locale)
        timezone = try container.decode(String.self, forKey: .timezone)
        defaultCurrencyCode = try container.decode(String.self, forKey: .defaultCurrencyCode)
        monthStartDay = try container.decodeIfPresent(Int.self, forKey: .monthStartDay) ?? 1
        weekStartDay = try container.decodeIfPresent(Int.self, forKey: .weekStartDay) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encodeIfPresent(locale, forKey: .locale)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(defaultCurrencyCode, forKey: .defaultCurrencyCode)
        try container.encode(monthStartDay, forKey: .monthStartDay)
        try container.encode(weekStartDay, forKey: .weekStartDay)
    }
}

public struct RemoteProfileUpdatePayload: Encodable, Sendable {
    public let defaultCurrencyCode: String?
    public let monthStartDay: Int?
    public let weekStartDay: Int?

    public init(
        defaultCurrencyCode: String? = nil,
        monthStartDay: Int? = nil,
        weekStartDay: Int? = nil
    ) {
        self.defaultCurrencyCode = defaultCurrencyCode
        self.monthStartDay = monthStartDay
        self.weekStartDay = weekStartDay
    }

    enum CodingKeys: String, CodingKey {
        case defaultCurrencyCode = "default_currency_code"
        case monthStartDay = "month_start_day"
        case weekStartDay = "week_start_day"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(defaultCurrencyCode, forKey: .defaultCurrencyCode)
        try container.encodeIfPresent(monthStartDay, forKey: .monthStartDay)
        try container.encodeIfPresent(weekStartDay, forKey: .weekStartDay)
    }
}

public struct RemoteSubscriptionSummaryDTO: Codable, Equatable, Sendable {
    public let activeCount: Int
    public let pausedCount: Int
    public let nextBillingDate: RemoteDateOnly?

    enum CodingKeys: String, CodingKey {
        case activeCount = "active_count"
        case pausedCount = "paused_count"
        case nextBillingDate = "next_billing_date"
    }
}

public struct RemoteBootstrapDTO: Codable, Equatable, Sendable {
    public let profile: RemoteProfileDTO
    public let accounts: [RemoteAccountDTO]
    public let categories: [RemoteCategoryDTO]
    public let subscriptionSummary: RemoteSubscriptionSummaryDTO

    enum CodingKeys: String, CodingKey {
        case profile
        case accounts
        case categories
        case subscriptionSummary = "subscription_summary"
    }
}

public struct RemoteHealthDTO: Codable, Equatable, Sendable {
    public let status: String
}
