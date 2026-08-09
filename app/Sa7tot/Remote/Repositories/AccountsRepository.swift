import Foundation

public struct RemoteAccountsRepository: Sendable {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func list() async throws -> [RemoteAccountDTO] {
        try await client.send(
            APIRequest<[RemoteAccountDTO]>(method: .get, path: "/v1/accounts")
        )
    }

    public func create(_ payload: RemoteAccountCreatePayload) async throws -> RemoteAccountDTO {
        try await client.post(RemoteAccountDTO.self, path: "/v1/accounts", body: payload)
    }

    public func update(accountID: UUID, _ payload: RemoteAccountUpdatePayload) async throws -> RemoteAccountDTO {
        try await client.patch(RemoteAccountDTO.self, path: "/v1/accounts/\(accountID.uuidString)", body: payload)
    }

    public func archive(accountID: UUID) async throws -> RemoteAccountDTO {
        try await client.post(RemoteAccountDTO.self, path: "/v1/accounts/\(accountID.uuidString)/archive", body: EmptyRequest())
    }
}

private struct EmptyRequest: Encodable {}
