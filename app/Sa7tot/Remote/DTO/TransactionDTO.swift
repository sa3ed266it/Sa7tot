import Foundation

public enum RemoteTransactionKind: String, Codable, Sendable {
    case expense
    case income
    case transfer
}

public enum RemoteRecurrenceKind: String, Codable, Sendable {
    case expense
    case income
}

public enum RemoteRecurrenceCadence: String, Codable, Sendable {
    case daily
    case weekly
    case monthly
}

public enum RemoteRecurrenceStatus: String, Codable, Sendable {
    case active
    case paused
    case cancelled
}

public struct RemoteRecurrenceBriefDTO: Codable, Equatable, Sendable {
    public let ruleID: UUID
    public let occurrenceID: UUID
    public let scheduledDate: RemoteDateOnly

    enum CodingKeys: String, CodingKey {
        case ruleID = "rule_id"
        case occurrenceID = "occurrence_id"
        case scheduledDate = "scheduled_date"
    }
}

public struct RemoteTransferDTO: Codable, Equatable, Sendable {
    public let sourceAccountID: UUID
    public let sourceAccountName: String
    public let destinationAccountID: UUID
    public let destinationAccountName: String

    enum CodingKeys: String, CodingKey {
        case sourceAccountID = "source_account_id"
        case sourceAccountName = "source_account_name"
        case destinationAccountID = "destination_account_id"
        case destinationAccountName = "destination_account_name"
    }
}

public struct RemoteTransactionDTO: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let userID: UUID
    public let kind: RemoteTransactionKind
    public let accountID: UUID
    public let destinationAccountID: UUID?
    public let amountMinor: Int64
    public let currencyCode: String
    public let currencyExponent: Int
    public let occurredAt: Date
    public let localDay: RemoteDateOnly
    public let title: String
    public let effectiveAmountMinor: Int64?
    public let category: RemoteCategoryBriefDTO?
    public let transfer: RemoteTransferDTO?
    public let subscription: RemoteSubscriptionBriefDTO?
    public let recurrence: RemoteRecurrenceBriefDTO?
    public let note: String?
    public let merchant: String?
    public let origin: String?
    public let reviewStatus: String?
    public let externalReference: String?
    public let createdAt: Date
    public let updatedAt: Date

    public var amount: RemoteMoney {
        RemoteMoney(minorUnits: amountMinor, currencyCode: currencyCode, exponent: currencyExponent)
    }

    public var effectiveAmount: RemoteMoney? {
        guard let effectiveAmountMinor else { return nil }
        return RemoteMoney(minorUnits: effectiveAmountMinor, currencyCode: currencyCode, exponent: currencyExponent)
    }

    public var allowsDirectMutation: Bool {
        subscription == nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case kind
        case accountID = "account_id"
        case destinationAccountID = "destination_account_id"
        case amountMinor = "amount_minor"
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case occurredAt = "occurred_at"
        case localDay = "local_day"
        case title
        case effectiveAmountMinor = "effective_amount_minor"
        case category
        case transfer
        case subscription
        case recurrence
        case note
        case merchant
        case origin
        case reviewStatus = "review_status"
        case externalReference = "external_reference"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct RemoteRecurrenceRuleDTO: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let userID: UUID
    public let accountID: UUID
    public let categoryID: UUID?
    public let kind: RemoteRecurrenceKind
    public let amountMinor: Int64
    public let currencyCode: String
    public let currencyExponent: Int
    public let title: String?
    public let note: String?
    public let merchant: String?
    public let cadence: RemoteRecurrenceCadence
    public let cadenceInterval: Int
    public let anchorDate: RemoteDateOnly
    public let nextOccurrenceDate: RemoteDateOnly
    public let status: RemoteRecurrenceStatus
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case accountID = "account_id"
        case categoryID = "category_id"
        case kind
        case amountMinor = "amount_minor"
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case title, note, merchant, cadence
        case cadenceInterval = "cadence_interval"
        case anchorDate = "anchor_date"
        case nextOccurrenceDate = "next_occurrence_date"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct RemoteRecurrenceCreatePayload: Encodable, Sendable {
    public let accountID: UUID
    public let categoryID: UUID?
    public let kind: RemoteRecurrenceKind
    public let amountMinor: Int64
    public let currencyCode: String
    public let currencyExponent: Int
    public let title: String?
    public let note: String?
    public let merchant: String?
    public let cadence: RemoteRecurrenceCadence
    public let cadenceInterval: Int
    public let anchorDate: RemoteDateOnly
    public let status: RemoteRecurrenceStatus

    public init(accountID: UUID, categoryID: UUID?, kind: RemoteRecurrenceKind, amountMinor: Int64, currencyCode: String, currencyExponent: Int, title: String? = nil, note: String? = nil, merchant: String? = nil, cadence: RemoteRecurrenceCadence, cadenceInterval: Int = 1, anchorDate: RemoteDateOnly, status: RemoteRecurrenceStatus = .active) {
        self.accountID = accountID
        self.categoryID = categoryID
        self.kind = kind
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.currencyExponent = currencyExponent
        self.title = title
        self.note = note
        self.merchant = merchant
        self.cadence = cadence
        self.cadenceInterval = cadenceInterval
        self.anchorDate = anchorDate
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case categoryID = "category_id"
        case kind
        case amountMinor = "amount_minor"
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case title, note, merchant, cadence
        case cadenceInterval = "cadence_interval"
        case anchorDate = "anchor_date"
        case status
    }
}

public struct RemoteRecurrenceUpdatePayload: Encodable, Sendable {
    public let accountID: UUID?
    public let categoryID: UUID?
    public let kind: RemoteRecurrenceKind?
    public let amountMinor: Int64?
    public let currencyCode: String?
    public let currencyExponent: Int?
    public let title: String?
    public let note: String?
    public let merchant: String?
    public let cadence: RemoteRecurrenceCadence?
    public let cadenceInterval: Int?
    public let anchorDate: RemoteDateOnly?

    public init(accountID: UUID? = nil, categoryID: UUID? = nil, kind: RemoteRecurrenceKind? = nil, amountMinor: Int64? = nil, currencyCode: String? = nil, currencyExponent: Int? = nil, title: String? = nil, note: String? = nil, merchant: String? = nil, cadence: RemoteRecurrenceCadence? = nil, cadenceInterval: Int? = nil, anchorDate: RemoteDateOnly? = nil) {
        self.accountID = accountID
        self.categoryID = categoryID
        self.kind = kind
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.currencyExponent = currencyExponent
        self.title = title
        self.note = note
        self.merchant = merchant
        self.cadence = cadence
        self.cadenceInterval = cadenceInterval
        self.anchorDate = anchorDate
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case categoryID = "category_id"
        case kind
        case amountMinor = "amount_minor"
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case title, note, merchant, cadence
        case cadenceInterval = "cadence_interval"
        case anchorDate = "anchor_date"
    }
}

public struct RemoteRecurrenceMaterializationDTO: Codable, Equatable, Sendable {
    public let generatedCount: Int
    public let skippedArchivedAccountCount: Int
    public let skippedInvalidCategoryCount: Int
    public let skippedCurrencyMismatchCount: Int

    enum CodingKeys: String, CodingKey {
        case generatedCount = "generated_count"
        case skippedArchivedAccountCount = "skipped_archived_account_count"
        case skippedInvalidCategoryCount = "skipped_invalid_category_count"
        case skippedCurrencyMismatchCount = "skipped_currency_mismatch_count"
    }
}

public struct RemoteTransactionCreatePayload: Encodable, Sendable {
    public let kind: RemoteTransactionKind
    public let accountID: UUID
    public let amountMinor: Int64
    public let currencyCode: String
    public let currencyExponent: Int
    public let occurredAt: Date
    public let categoryID: UUID?
    public let note: String?
    public let merchant: String?
    public let origin: String?
    public let reviewStatus: String?

    public init(kind: RemoteTransactionKind, accountID: UUID, amountMinor: Int64, currencyCode: String, currencyExponent: Int, occurredAt: Date, categoryID: UUID? = nil, note: String? = nil, merchant: String? = nil, origin: String? = "manual", reviewStatus: String? = "confirmed") {
        self.kind = kind
        self.accountID = accountID
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.currencyExponent = currencyExponent
        self.occurredAt = occurredAt
        self.categoryID = categoryID
        self.note = note
        self.merchant = merchant
        self.origin = origin
        self.reviewStatus = reviewStatus
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case accountID = "account_id"
        case amountMinor = "amount_minor"
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case occurredAt = "occurred_at"
        case categoryID = "category_id"
        case note, merchant, origin
        case reviewStatus = "review_status"
    }
}

public struct RemoteTransactionUpdatePayload: Encodable, Sendable {
    public let kind: RemoteTransactionKind?
    public let accountID: UUID?
    public let amountMinor: Int64?
    public let currencyCode: String?
    public let currencyExponent: Int?
    public let occurredAt: Date?
    public let categoryID: UUID?
    public let note: String?
    public let merchant: String?
    public let origin: String?
    public let reviewStatus: String?

    public init(kind: RemoteTransactionKind? = nil, accountID: UUID? = nil, amountMinor: Int64? = nil, currencyCode: String? = nil, currencyExponent: Int? = nil, occurredAt: Date? = nil, categoryID: UUID? = nil, note: String? = nil, merchant: String? = nil, origin: String? = nil, reviewStatus: String? = nil) {
        self.kind = kind
        self.accountID = accountID
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.currencyExponent = currencyExponent
        self.occurredAt = occurredAt
        self.categoryID = categoryID
        self.note = note
        self.merchant = merchant
        self.origin = origin
        self.reviewStatus = reviewStatus
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case accountID = "account_id"
        case amountMinor = "amount_minor"
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case occurredAt = "occurred_at"
        case categoryID = "category_id"
        case note, merchant, origin
        case reviewStatus = "review_status"
    }
}

public struct RemoteTransferCreatePayload: Encodable, Sendable {
    public let sourceAccountID: UUID
    public let destinationAccountID: UUID
    public let amountMinor: Int64
    public let currencyCode: String
    public let currencyExponent: Int
    public let occurredAt: Date
    public let note: String?

    public init(sourceAccountID: UUID, destinationAccountID: UUID, amountMinor: Int64, currencyCode: String, currencyExponent: Int, occurredAt: Date, note: String? = nil) {
        self.sourceAccountID = sourceAccountID
        self.destinationAccountID = destinationAccountID
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.currencyExponent = currencyExponent
        self.occurredAt = occurredAt
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case sourceAccountID = "source_account_id"
        case destinationAccountID = "destination_account_id"
        case amountMinor = "amount_minor"
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case occurredAt = "occurred_at"
        case note
    }
}
