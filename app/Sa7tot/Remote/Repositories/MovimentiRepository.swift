import Foundation

public protocol RemoteMovimentiPageProviding: Sendable {
    func page(
        accountID: UUID,
        limit: Int?,
        cursor: String?,
        filter: String?,
        income: Bool?,
        day: RemoteDateOnly?,
        weekStart: RemoteDateOnly?,
        month: String?,
        categoryID: UUID?
    ) async throws -> RemoteMovimentiPageDTO
}

public struct RemoteMovimentiRepository: Sendable, RemoteMovimentiPageProviding {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func page(
        accountID: UUID,
        limit: Int? = nil,
        cursor: String? = nil,
        filter: String? = nil,
        income: Bool? = nil,
        day: RemoteDateOnly? = nil,
        weekStart: RemoteDateOnly? = nil,
        month: String? = nil,
        categoryID: UUID? = nil
    ) async throws -> RemoteMovimentiPageDTO {
        var queryItems: [URLQueryItem] = []
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let filter {
            queryItems.append(URLQueryItem(name: "filter", value: filter))
        }
        if let income {
            queryItems.append(URLQueryItem(name: "income", value: income ? "true" : "false"))
        }
        if let day {
            queryItems.append(URLQueryItem(name: "day", value: day.isoString))
        }
        if let weekStart {
            queryItems.append(URLQueryItem(name: "week_start", value: weekStart.isoString))
        }
        if let month {
            queryItems.append(URLQueryItem(name: "month", value: month))
        }
        if let categoryID {
            queryItems.append(URLQueryItem(name: "category_id", value: categoryID.uuidString))
        }

        return try await client.send(
            APIRequest<RemoteMovimentiPageDTO>(
                method: .get,
                path: "/v1/accounts/\(accountID.uuidString)/movements",
                queryItems: queryItems
            )
        )
    }
}

public struct RemoteUpcomingRepository: Sendable {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func list(accountID: UUID, limit: Int? = nil, days: Int? = nil, until: RemoteDateOnly? = nil) async throws -> RemoteUpcomingResponseDTO {
        var queryItems: [URLQueryItem] = []
        if let limit { queryItems.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let days { queryItems.append(URLQueryItem(name: "days", value: String(days))) }
        if let until { queryItems.append(URLQueryItem(name: "until", value: until.isoString)) }
        return try await client.get(
            RemoteUpcomingResponseDTO.self,
            path: "/v1/accounts/\(accountID.uuidString)/upcoming",
            queryItems: queryItems
        )
    }
}
