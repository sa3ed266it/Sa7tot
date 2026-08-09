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
        case let .invalidURL(message): return message
        case .missingTokenProvider: return "An authenticated request requires an access token provider."
        case let .unauthorized(message): return message ?? "The request is not authorized."
        case let .forbidden(message): return message ?? "The request is forbidden."
        case let .notFound(message): return message ?? "The requested resource was not found."
        case let .validation(message): return message ?? "The request was invalid."
        case let .server(statusCode, message): return message ?? "The server returned HTTP \(statusCode)."
        case let .transport(message): return message
        case .invalidResponse: return "The server returned an invalid response."
        case let .decoding(message): return message
        }
    }
}
