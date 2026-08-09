import Foundation

public struct RemoteProfileDTO: Codable, Equatable, Sendable {
    public let userID: UUID
    public let locale: String?
    public let timezone: String
    public let defaultCurrencyCode: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case locale
        case timezone
        case defaultCurrencyCode = "default_currency_code"
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
