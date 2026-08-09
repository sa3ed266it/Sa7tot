import Foundation

public enum RemoteSubscriptionStatus: String, Codable, Sendable {
    case active
    case paused
    case cancelled
}

public enum RemoteSubscriptionCadence: String, Codable, Sendable {
    case weekly
    case monthly
    case yearly
}

public struct RemoteSubscriptionBriefDTO: Codable, Equatable, Sendable {
    public let id: UUID?
    public let serviceID: String?
    public let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case serviceID = "service_id"
        case displayName = "display_name"
    }
}

public struct RemoteSubscriptionDTO: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let userID: UUID
    public let accountID: UUID
    public let categoryID: UUID?
    public let serviceID: String?
    public let customName: String?
    public let displayName: String
    public let amountMinor: Int64
    public let currencyCode: String
    public let currencyExponent: Int
    public let cadence: RemoteSubscriptionCadence
    public let cadenceInterval: Int
    public let billingAnchor: RemoteDateOnly
    public let nextBillingDate: RemoteDateOnly
    public let status: RemoteSubscriptionStatus
    public let note: String?
    public let createdAt: Date
    public let updatedAt: Date

    public var amount: RemoteMoney {
        RemoteMoney(minorUnits: amountMinor, currencyCode: currencyCode, exponent: currencyExponent)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case accountID = "account_id"
        case categoryID = "category_id"
        case serviceID = "service_id"
        case customName = "custom_name"
        case displayName = "display_name"
        case amountMinor = "amount_minor"
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case cadence
        case cadenceInterval = "cadence_interval"
        case billingAnchor = "billing_anchor"
        case nextBillingDate = "next_billing_date"
        case status
        case note
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct RemoteSubscriptionCreatePayload: Encodable, Sendable {
    public let accountID: UUID
    public let categoryID: UUID?
    public let serviceID: String?
    public let customName: String?
    public let amountMinor: Int64
    public let currencyCode: String
    public let currencyExponent: Int
    public let cadence: RemoteSubscriptionCadence
    public let cadenceInterval: Int
    public let billingAnchor: RemoteDateOnly
    public let note: String?

    public init(
        accountID: UUID,
        categoryID: UUID? = nil,
        serviceID: String? = nil,
        customName: String? = nil,
        amountMinor: Int64,
        currencyCode: String,
        currencyExponent: Int,
        cadence: RemoteSubscriptionCadence,
        cadenceInterval: Int = 1,
        billingAnchor: RemoteDateOnly,
        note: String? = nil
    ) {
        self.accountID = accountID
        self.categoryID = categoryID
        self.serviceID = serviceID
        self.customName = customName
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.currencyExponent = currencyExponent
        self.cadence = cadence
        self.cadenceInterval = cadenceInterval
        self.billingAnchor = billingAnchor
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case categoryID = "category_id"
        case serviceID = "service_id"
        case customName = "custom_name"
        case amountMinor = "amount_minor"
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case cadence
        case cadenceInterval = "cadence_interval"
        case billingAnchor = "billing_anchor"
        case note
    }
}

public struct RemoteSubscriptionUpdatePayload: Encodable, Sendable {
    public let accountID: UUID?
    public let categoryID: UUID?
    public let serviceID: String?
    public let customName: String?
    public let amountMinor: Int64?
    public let currencyCode: String?
    public let currencyExponent: Int?
    public let cadence: RemoteSubscriptionCadence?
    public let cadenceInterval: Int?
    public let billingAnchor: RemoteDateOnly?
    public let note: String?

    public init(
        accountID: UUID? = nil,
        categoryID: UUID? = nil,
        serviceID: String? = nil,
        customName: String? = nil,
        amountMinor: Int64? = nil,
        currencyCode: String? = nil,
        currencyExponent: Int? = nil,
        cadence: RemoteSubscriptionCadence? = nil,
        cadenceInterval: Int? = nil,
        billingAnchor: RemoteDateOnly? = nil,
        note: String? = nil
    ) {
        self.accountID = accountID
        self.categoryID = categoryID
        self.serviceID = serviceID
        self.customName = customName
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.currencyExponent = currencyExponent
        self.cadence = cadence
        self.cadenceInterval = cadenceInterval
        self.billingAnchor = billingAnchor
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case categoryID = "category_id"
        case serviceID = "service_id"
        case customName = "custom_name"
        case amountMinor = "amount_minor"
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case cadence
        case cadenceInterval = "cadence_interval"
        case billingAnchor = "billing_anchor"
        case note
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serviceID, forKey: .serviceID)
        try container.encode(customName, forKey: .customName)
        try container.encodeIfPresent(accountID, forKey: .accountID)
        try container.encodeIfPresent(categoryID, forKey: .categoryID)
        try container.encodeIfPresent(amountMinor, forKey: .amountMinor)
        try container.encodeIfPresent(currencyCode, forKey: .currencyCode)
        try container.encodeIfPresent(currencyExponent, forKey: .currencyExponent)
        try container.encodeIfPresent(cadence, forKey: .cadence)
        try container.encodeIfPresent(cadenceInterval, forKey: .cadenceInterval)
        try container.encodeIfPresent(billingAnchor, forKey: .billingAnchor)
        try container.encodeIfPresent(note, forKey: .note)
    }
}

public struct RemoteSubscriptionMaterializationDTO: Codable, Equatable, Sendable {
    public let generatedCount: Int
    public let skippedArchivedAccountCount: Int

    enum CodingKeys: String, CodingKey {
        case generatedCount = "generated_count"
        case skippedArchivedAccountCount = "skipped_archived_account_count"
    }
}
