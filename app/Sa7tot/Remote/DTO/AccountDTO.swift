import Foundation

public struct RemoteAccountDTO: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let userID: UUID
    public let name: String
    public let type: String
    public let currencyCode: String
    public let currencyExponent: Int
    public let openingBalanceMinor: Int64
    public let iconName: String
    public let color: String
    public let walletLabel: String?
    public let isArchived: Bool
    public let sortOrder: Int
    public let createdAt: Date
    public let updatedAt: Date

    public var openingBalance: RemoteMoney {
        RemoteMoney(minorUnits: openingBalanceMinor, currencyCode: currencyCode, exponent: currencyExponent)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case type
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case openingBalanceMinor = "opening_balance_minor"
        case iconName = "icon_name"
        case color
        case walletLabel = "wallet_label"
        case isArchived = "is_archived"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct RemoteAccountSnapshotDTO: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let currencyCode: String
    public let currencyExponent: Int
    public let balanceMinor: Int64

    public var balance: RemoteMoney {
        RemoteMoney(minorUnits: balanceMinor, currencyCode: currencyCode, exponent: currencyExponent)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case balanceMinor = "balance_minor"
    }
}

public struct RemoteAccountCreatePayload: Encodable, Sendable {
    public let name: String
    public let type: String
    public let currencyCode: String
    public let currencyExponent: Int
    public let openingBalanceMinor: Int64
    public let iconName: String
    public let color: String
    public let walletLabel: String?
    public let isArchived: Bool
    public let sortOrder: Int

    public init(
        name: String,
        type: String = "other",
        currencyCode: String,
        currencyExponent: Int,
        openingBalanceMinor: Int64 = 0,
        iconName: String = "building.columns.fill",
        color: String = "#5E7CE2",
        walletLabel: String? = nil,
        isArchived: Bool = false,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.type = type
        self.currencyCode = currencyCode
        self.currencyExponent = currencyExponent
        self.openingBalanceMinor = openingBalanceMinor
        self.iconName = iconName
        self.color = color
        self.walletLabel = walletLabel
        self.isArchived = isArchived
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case name, type
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case openingBalanceMinor = "opening_balance_minor"
        case iconName = "icon_name"
        case color
        case walletLabel = "wallet_label"
        case isArchived = "is_archived"
        case sortOrder = "sort_order"
    }
}

public struct RemoteAccountUpdatePayload: Encodable, Sendable {
    public let name: String?
    public let type: String?
    public let currencyCode: String?
    public let currencyExponent: Int?
    public let openingBalanceMinor: Int64?
    public let iconName: String?
    public let color: String?
    public let walletLabel: String?
    public let sortOrder: Int?

    public init(
        name: String? = nil,
        type: String? = nil,
        currencyCode: String? = nil,
        currencyExponent: Int? = nil,
        openingBalanceMinor: Int64? = nil,
        iconName: String? = nil,
        color: String? = nil,
        walletLabel: String? = nil,
        sortOrder: Int? = nil
    ) {
        self.name = name
        self.type = type
        self.currencyCode = currencyCode
        self.currencyExponent = currencyExponent
        self.openingBalanceMinor = openingBalanceMinor
        self.iconName = iconName
        self.color = color
        self.walletLabel = walletLabel
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case name, type
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case openingBalanceMinor = "opening_balance_minor"
        case iconName = "icon_name"
        case color
        case walletLabel = "wallet_label"
        case sortOrder = "sort_order"
    }
}
