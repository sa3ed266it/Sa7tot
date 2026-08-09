import Foundation

public struct RemoteMovementSummaryDTO: Codable, Equatable, Sendable {
    public let incomeMinor: Int64
    public let expensesMinor: Int64

    enum CodingKeys: String, CodingKey {
        case incomeMinor = "income_minor"
        case expensesMinor = "expenses_minor"
    }
}

public struct RemoteMovementDayDTO: Codable, Equatable, Sendable {
    public let day: RemoteDateOnly
    public let subtotalMinor: Int64
    public let movements: [RemoteTransactionDTO]

    enum CodingKeys: String, CodingKey {
        case day
        case subtotalMinor = "subtotal_minor"
        case movements
    }
}

public struct RemoteMovimentiPageDTO: Codable, Equatable, Sendable {
    public let account: RemoteAccountSnapshotDTO
    public let summary: RemoteMovementSummaryDTO
    public let days: [RemoteMovementDayDTO]
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case account
        case summary
        case days
        case nextCursor = "next_cursor"
    }
}

public struct RemoteUpcomingTransactionItemDTO: Codable, Equatable, Sendable {
    public let kind: String
    public let effectiveDate: RemoteDateOnly
    public let transaction: RemoteTransactionDTO

    enum CodingKeys: String, CodingKey {
        case kind
        case effectiveDate = "effective_date"
        case transaction
    }
}

public struct RemoteUpcomingRecurrenceItemDTO: Codable, Equatable, Sendable {
    public let kind: String
    public let effectiveDate: RemoteDateOnly
    public let ruleID: UUID
    public let scheduledDate: RemoteDateOnly
    public let account: RemoteAccountBriefDTO
    public let category: RemoteCategoryBriefDTO?
    public let transactionKind: RemoteRecurrenceKind
    public let amountMinor: Int64
    public let currencyCode: String
    public let currencyExponent: Int
    public let title: String?
    public let note: String?
    public let merchant: String?
    public let cadence: RemoteRecurrenceCadence
    public let cadenceInterval: Int

    enum CodingKeys: String, CodingKey {
        case kind
        case effectiveDate = "effective_date"
        case ruleID = "rule_id"
        case scheduledDate = "scheduled_date"
        case account, category
        case transactionKind = "transaction_kind"
        case amountMinor = "amount_minor"
        case currencyCode = "currency_code"
        case currencyExponent = "currency_exponent"
        case title, note, merchant, cadence
        case cadenceInterval = "cadence_interval"
    }
}

public enum RemoteUpcomingItemDTO: Equatable, Identifiable, Sendable {
    case transaction(RemoteUpcomingTransactionItemDTO)
    case recurrence(RemoteUpcomingRecurrenceItemDTO)

    public var id: String {
        switch self {
        case let .transaction(item): return "transaction-\(item.transaction.id.uuidString)"
        case let .recurrence(item): return "recurrence-\(item.ruleID.uuidString)-\(item.scheduledDate.isoString)"
        }
    }

    public var effectiveDate: RemoteDateOnly {
        switch self {
        case let .transaction(item): return item.effectiveDate
        case let .recurrence(item): return item.effectiveDate
        }
    }
}

extension RemoteUpcomingItemDTO: Decodable {
    private enum CodingKeys: String, CodingKey { case kind }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "transaction": self = .transaction(try RemoteUpcomingTransactionItemDTO(from: decoder))
        case "recurrence": self = .recurrence(try RemoteUpcomingRecurrenceItemDTO(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown upcoming item kind.")
        }
    }
}

public struct RemoteUpcomingResponseDTO: Decodable, Equatable, Sendable {
    public let account: RemoteAccountBriefDTO
    public let items: [RemoteUpcomingItemDTO]
}

public struct RemoteAccountBriefDTO: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let currencyCode: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case currencyCode = "currency_code"
    }
}
