import Foundation

public struct RemotePushDevicesRepository: Sendable {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func register(
        token: String,
        environment: RemotePushEnvironment,
        appVersion: String?
    ) async throws -> RemotePushDeviceRegistrationDTO {
        try await client.put(
            RemotePushDeviceRegistrationDTO.self,
            path: "/v1/push/devices",
            body: RemotePushDeviceRegistrationPayload(
                token: token,
                environment: environment,
                appVersion: appVersion
            )
        )
    }

    public func deactivate(token: String) async throws -> RemotePushDeviceDeactivationDTO {
        try await client.delete(
            RemotePushDeviceDeactivationDTO.self,
            path: "/v1/push/devices/\(token.lowercased())"
        )
    }
}
