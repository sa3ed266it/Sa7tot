import Foundation

public struct RemoteTransactionsRepository: Sendable {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func get(transactionID: UUID) async throws -> RemoteTransactionDTO {
        try await client.get(RemoteTransactionDTO.self, path: "/v1/transactions/\(transactionID.uuidString)")
    }

    public func create(_ payload: RemoteTransactionCreatePayload) async throws -> RemoteTransactionDTO {
        try await client.post(RemoteTransactionDTO.self, path: "/v1/transactions", body: payload)
    }

    public func update(transactionID: UUID, _ payload: RemoteTransactionUpdatePayload) async throws -> RemoteTransactionDTO {
        try await client.patch(RemoteTransactionDTO.self, path: "/v1/transactions/\(transactionID.uuidString)", body: payload)
    }

    public func delete(transactionID: UUID) async throws {
        _ = try await client.delete(EmptyResponse.self, path: "/v1/transactions/\(transactionID.uuidString)")
    }

    public func createTransfer(_ payload: RemoteTransferCreatePayload) async throws -> RemoteTransactionDTO {
        try await client.post(RemoteTransactionDTO.self, path: "/v1/transfers", body: payload)
    }
}

public struct RemoteRecurrencesRepository: Sendable {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func list() async throws -> [RemoteRecurrenceRuleDTO] {
        try await client.get([RemoteRecurrenceRuleDTO].self, path: "/v1/recurrences")
    }

    public func create(_ payload: RemoteRecurrenceCreatePayload) async throws -> RemoteRecurrenceRuleDTO {
        try await client.post(RemoteRecurrenceRuleDTO.self, path: "/v1/recurrences", body: payload)
    }

    public func update(ruleID: UUID, _ payload: RemoteRecurrenceUpdatePayload) async throws -> RemoteRecurrenceRuleDTO {
        try await client.patch(RemoteRecurrenceRuleDTO.self, path: "/v1/recurrences/\(ruleID.uuidString)", body: payload)
    }

    public func pause(ruleID: UUID) async throws -> RemoteRecurrenceRuleDTO {
        try await status(ruleID: ruleID, action: "pause")
    }

    public func resume(ruleID: UUID) async throws -> RemoteRecurrenceRuleDTO {
        try await status(ruleID: ruleID, action: "resume")
    }

    public func cancel(ruleID: UUID) async throws -> RemoteRecurrenceRuleDTO {
        try await status(ruleID: ruleID, action: "cancel")
    }

    public func materialize() async throws -> RemoteRecurrenceMaterializationDTO {
        try await client.post(
            RemoteRecurrenceMaterializationDTO.self,
            path: "/v1/recurrences/materialize",
            body: EmptyRecurrenceRequest()
        )
    }

    private func status(ruleID: UUID, action: String) async throws -> RemoteRecurrenceRuleDTO {
        try await client.post(
            RemoteRecurrenceRuleDTO.self,
            path: "/v1/recurrences/\(ruleID.uuidString)/\(action)",
            body: EmptyRecurrenceRequest()
        )
    }
}

private struct EmptyRecurrenceRequest: Encodable {}
