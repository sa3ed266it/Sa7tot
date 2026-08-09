import Foundation

public struct RemoteHealthRepository: Sendable {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func check() async throws -> RemoteHealthDTO {
        try await client.send(
            APIRequest<RemoteHealthDTO>(
                method: .get,
                path: "/health",
                authentication: .public
            )
        )
    }
}
