import Foundation

public struct RemoteCategoryBriefDTO: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let income: Bool
    public let iconIdentifier: String
    public let color: String
    public let presetKey: String?

    public init(
        id: UUID,
        name: String,
        income: Bool,
        iconIdentifier: String,
        color: String,
        presetKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.income = income
        self.iconIdentifier = iconIdentifier
        self.color = color
        self.presetKey = presetKey
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case income
        case iconIdentifier = "icon_identifier"
        case color
        case presetKey = "preset_key"
    }
}

public struct RemoteCategoryDTO: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let userID: UUID
    public let name: String
    public let income: Bool
    public let iconIdentifier: String
    public let color: String
    public let sortOrder: Int
    public let presetKey: String?
    public let deletedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case income
        case iconIdentifier = "icon_identifier"
        case color
        case sortOrder = "sort_order"
        case presetKey = "preset_key"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct RemoteCategoryCreatePayload: Encodable, Sendable {
    public let name: String
    public let income: Bool
    public let iconIdentifier: String
    public let color: String
    public let sortOrder: Int

    public init(name: String, income: Bool, iconIdentifier: String = "sf:tag.fill", color: String = "#FFFFFF", sortOrder: Int = 0) {
        self.name = name
        self.income = income
        self.iconIdentifier = iconIdentifier
        self.color = color
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case name, income
        case iconIdentifier = "icon_identifier"
        case color
        case sortOrder = "sort_order"
    }
}

public struct RemoteCategoryUpdatePayload: Encodable, Sendable {
    public let name: String?
    public let income: Bool?
    public let iconIdentifier: String?
    public let color: String?
    public let sortOrder: Int?

    public init(name: String? = nil, income: Bool? = nil, iconIdentifier: String? = nil, color: String? = nil, sortOrder: Int? = nil) {
        self.name = name
        self.income = income
        self.iconIdentifier = iconIdentifier
        self.color = color
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case name, income
        case iconIdentifier = "icon_identifier"
        case color
        case sortOrder = "sort_order"
    }
}

public struct RemoteCategoryPresetActivationPayload: Encodable, Sendable {
    public let presetKey: String
    public let income: Bool?
    public let displayName: String?

    public init(presetKey: String, income: Bool? = nil, displayName: String? = nil) {
        self.presetKey = presetKey
        self.income = income
        self.displayName = displayName
    }

    enum CodingKeys: String, CodingKey {
        case presetKey = "preset_key"
        case income
        case displayName = "display_name"
    }
}
