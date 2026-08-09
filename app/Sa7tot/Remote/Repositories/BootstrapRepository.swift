import Foundation

public struct RemoteBootstrapRepository: Sendable {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func load() async throws -> RemoteBootstrapDTO {
        try await client.send(
            APIRequest<RemoteBootstrapDTO>(method: .get, path: "/v1/bootstrap")
        )
    }
}
