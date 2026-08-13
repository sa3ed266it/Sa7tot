import Foundation

public enum RemotePushEnvironment: String, Codable, Sendable {
    case development
    case production
}

public struct RemotePushDeviceRegistrationPayload: Encodable, Sendable {
    public let token: String
    public let platform: String
    public let environment: RemotePushEnvironment
    public let appVersion: String?

    public init(token: String, environment: RemotePushEnvironment, appVersion: String? = nil) {
        self.token = token
        self.platform = "ios"
        self.environment = environment
        self.appVersion = appVersion
    }

    enum CodingKeys: String, CodingKey {
        case token
        case platform
        case environment
        case appVersion = "app_version"
    }
}

public struct RemotePushDeviceRegistrationDTO: Decodable, Equatable, Sendable {
    public let id: UUID
    public let platform: String
    public let environment: RemotePushEnvironment
    public let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case platform
        case environment
        case isActive = "is_active"
    }
}

public struct RemotePushDeviceDeactivationDTO: Decodable, Equatable, Sendable {
    public let deactivated: Bool
}
