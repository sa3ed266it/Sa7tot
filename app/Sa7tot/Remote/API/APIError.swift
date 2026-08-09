import Foundation

public enum APIError: Error, Equatable, Sendable {
    case invalidURL(String)
    case missingTokenProvider
    case unauthorized(String?)
    case forbidden(String?)
    case notFound(String?)
    case validation(String?)
    case server(statusCode: Int, message: String?)
    case transport(String)
    case invalidResponse
    case decoding(String)
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL, .missingTokenProvider:
            return AppLocalization.string("error.configuration")
        case .unauthorized:
            return AppLocalization.string("error.unauthorized")
        case .forbidden:
            return AppLocalization.string("error.forbidden")
        case .notFound:
            return AppLocalization.string("error.notFound")
        case .validation:
            return AppLocalization.string("error.validation")
        case let .server(statusCode, _):
            return AppLocalization.format("error.server", statusCode)
        case .transport:
            return AppLocalization.string("error.network")
        case .invalidResponse, .decoding:
            return AppLocalization.string("error.invalidResponse")
        }
    }
}
