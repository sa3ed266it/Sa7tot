import Foundation

public struct RemoteSubscriptionsRepository: Sendable {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func list() async throws -> [RemoteSubscriptionDTO] {
        try await client.get([RemoteSubscriptionDTO].self, path: "/v1/subscriptions")
    }

    public func create(_ payload: RemoteSubscriptionCreatePayload) async throws -> RemoteSubscriptionDTO {
        try await client.post(RemoteSubscriptionDTO.self, path: "/v1/subscriptions", body: payload)
    }

    public func update(subscriptionID: UUID, _ payload: RemoteSubscriptionUpdatePayload) async throws -> RemoteSubscriptionDTO {
        try await client.patch(RemoteSubscriptionDTO.self, path: "/v1/subscriptions/\(subscriptionID.uuidString)", body: payload)
    }

    public func pause(subscriptionID: UUID) async throws -> RemoteSubscriptionDTO {
        try await status(subscriptionID: subscriptionID, action: "pause")
    }

    public func resume(subscriptionID: UUID) async throws -> RemoteSubscriptionDTO {
        try await status(subscriptionID: subscriptionID, action: "resume")
    }

    public func cancel(subscriptionID: UUID) async throws -> RemoteSubscriptionDTO {
        try await status(subscriptionID: subscriptionID, action: "cancel")
    }

    public func materialize() async throws -> RemoteSubscriptionMaterializationDTO {
        try await client.post(
            RemoteSubscriptionMaterializationDTO.self,
            path: "/v1/subscriptions/materialize",
            body: EmptySubscriptionRequest()
        )
    }

    private func status(subscriptionID: UUID, action: String) async throws -> RemoteSubscriptionDTO {
        try await client.post(
            RemoteSubscriptionDTO.self,
            path: "/v1/subscriptions/\(subscriptionID.uuidString)/\(action)",
            body: EmptySubscriptionRequest()
        )
    }
}

private struct EmptySubscriptionRequest: Encodable {}
