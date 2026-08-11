import Foundation

public struct RemoteMoney: Codable, Equatable, Hashable, Sendable {
    public let minorUnits: Int64
    public let currencyCode: String
    public let exponent: Int

    public init(minorUnits: Int64, currencyCode: String, exponent: Int) {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode
        self.exponent = exponent
    }
}

public struct RemoteDateOnly: Codable, Equatable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        guard let date = components.calendar?.date(from: components) else {
            throw DateOnlyError.invalidValue("\(year)-\(month)-\(day)")
        }
        let normalized = components.calendar?.dateComponents([.year, .month, .day], from: date)
        guard normalized?.year == year, normalized?.month == month, normalized?.day == day else {
            throw DateOnlyError.invalidValue("\(year)-\(month)-\(day)")
        }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(isoString: String) throws {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            throw DateOnlyError.invalidValue(isoString)
        }
        try self.init(year: year, month: month, day: day)
    }

    public var isoString: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { isoString }

    public init(from decoder: Decoder) throws {
        try self.init(isoString: decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }

    public static func < (lhs: RemoteDateOnly, rhs: RemoteDateOnly) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public enum DateOnlyError: Error, Equatable, Sendable {
    case invalidValue(String)
}

public enum RemoteJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatters: [ISO8601DateFormatter] = [
                configuredISOFormatter(fractionalSeconds: true),
                configuredISOFormatter(fractionalSeconds: false)
            ]
            if let date = formatters.compactMap({ $0.date(from: value) }).first {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Expected an ISO-8601 timestamp."
            )
        }
        return decoder
    }

    private static func configuredISOFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}

enum RemoteStartupFastPathDecision: Equatable {
    case useFreshCache
    case awaitSpeculativePage
    case fetchAuthoritativePage

    static func resolve(
        lastKnownAccountID: UUID?,
        authoritativeAccountID: UUID,
        speculativePageAccountID: UUID?,
        hasFreshCache: Bool,
        hasInFlightPage: Bool
    ) -> Self {
        guard lastKnownAccountID == authoritativeAccountID else {
            return .fetchAuthoritativePage
        }
        if hasFreshCache {
            return .useFreshCache
        }
        if hasInFlightPage, speculativePageAccountID == authoritativeAccountID {
            return .awaitSpeculativePage
        }
        return .fetchAuthoritativePage
    }

    static func canPublish(
        pageAccountID: UUID,
        intendedAccountID: UUID,
        expectedGeneration: Int,
        currentGeneration: Int,
        hasAuthoritativeAccountSet: Bool = true,
        isSpeculative: Bool = false
    ) -> Bool {
        pageAccountID == intendedAccountID
            && expectedGeneration == currentGeneration
            && (!isSpeculative || hasAuthoritativeAccountSet)
    }

    static func shouldDeferSpeculativePage(isSpeculative: Bool, hasAuthoritativeAccountSet: Bool) -> Bool {
        isSpeculative && !hasAuthoritativeAccountSet
    }
}

public enum RemoteBudgetPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case day, week, month, year
    public var id: String { rawValue }
}

public struct RemoteMainBudgetDTO: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let amountMinor: Int64
    public let spentMinor: Int64
    public let remainingMinor: Int64
    public let progress: Double
    public let currencyCode: String
    public let currencyExponent: Int
    public let periodType: RemoteBudgetPeriod
    public let periodStart: RemoteDateOnly
    public let periodEnd: RemoteDateOnly
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, amountMinor = "amount_minor", spentMinor = "spent_minor", remainingMinor = "remaining_minor"
        case progress, currencyCode = "currency_code", currencyExponent = "currency_exponent"
        case periodType = "period_type", periodStart = "period_start", periodEnd = "period_end"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
}

public struct RemoteCategoryBudgetDTO: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let categoryID: UUID
    public let categoryName: String?
    public let categoryDeleted: Bool
    public let categoryIconIdentifier: String?
    public let categoryColor: String?
    public let amountMinor: Int64
    public let spentMinor: Int64
    public let remainingMinor: Int64
    public let progress: Double
    public let currencyCode: String
    public let currencyExponent: Int
    public let periodType: RemoteBudgetPeriod
    public let periodStart: RemoteDateOnly
    public let periodEnd: RemoteDateOnly
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, categoryID = "category_id", categoryName = "category_name", categoryDeleted = "category_deleted"
        case categoryIconIdentifier = "category_icon_identifier", categoryColor = "category_color"
        case amountMinor = "amount_minor", spentMinor = "spent_minor", remainingMinor = "remaining_minor"
        case progress, currencyCode = "currency_code", currencyExponent = "currency_exponent"
        case periodType = "period_type", periodStart = "period_start", periodEnd = "period_end"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
}

public struct RemoteBudgetSummaryDTO: Codable, Equatable, Sendable {
    public let main: RemoteMainBudgetDTO?
    public let categories: [RemoteCategoryBudgetDTO]
}

public struct RemoteBudgetMutationPayload: Encodable, Sendable {
    public let amountMinor: Int64
    public let currencyCode: String
    public let currencyExponent: Int
    public let periodType: RemoteBudgetPeriod
    public let periodStart: RemoteDateOnly?

    public init(amountMinor: Int64, currencyCode: String, currencyExponent: Int, periodType: RemoteBudgetPeriod, periodStart: RemoteDateOnly? = nil) {
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.currencyExponent = currencyExponent
        self.periodType = periodType
        self.periodStart = periodStart
    }

    enum CodingKeys: String, CodingKey {
        case amountMinor = "amount_minor", currencyCode = "currency_code", currencyExponent = "currency_exponent"
        case periodType = "period_type", periodStart = "period_start"
    }
}

public struct RemoteBudgetRepository: Sendable {
    private let client: APIClient
    public init(client: APIClient) { self.client = client }
    public func get() async throws -> RemoteBudgetSummaryDTO {
        try await client.get(RemoteBudgetSummaryDTO.self, path: "/v1/budget")
    }
    public func upsertMain(_ payload: RemoteBudgetMutationPayload) async throws -> RemoteBudgetSummaryDTO {
        try await client.put(RemoteBudgetSummaryDTO.self, path: "/v1/budget/main", body: payload)
    }
    public func upsertCategory(categoryID: UUID, _ payload: RemoteBudgetMutationPayload) async throws -> RemoteBudgetSummaryDTO {
        try await client.put(RemoteBudgetSummaryDTO.self, path: "/v1/budget/categories/\(categoryID.uuidString)", body: payload)
    }
    public func deleteMain() async throws -> RemoteBudgetSummaryDTO {
        try await client.delete(RemoteBudgetSummaryDTO.self, path: "/v1/budget/main")
    }
    public func deleteCategory(categoryID: UUID) async throws -> RemoteBudgetSummaryDTO {
        try await client.delete(RemoteBudgetSummaryDTO.self, path: "/v1/budget/categories/\(categoryID.uuidString)")
    }
}
