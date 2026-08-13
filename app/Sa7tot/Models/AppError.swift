import Foundation

/// Central application error taxonomy.
public enum AppError: Error, Equatable, Sendable {
    // Transport
    case networkUnavailable
    case connectionFailed
    case timeout

    // Server / HTTP
    case serverUnavailable(statusCode: Int)
    case unauthorized
    case forbidden
    case notFound
    case conflict(message: String?)
    case validation(message: String?)
    case rateLimited(retryAfter: Int?)

    // Client / System
    case decoding(details: String?)
    case invalidResponse
    case configuration
    case cancelled
    case unknown(message: String?)
}

extension AppError {
    public static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        if let apiError = error as? APIError {
            return from(apiError: apiError)
        }
        if let urlError = error as? URLError {
            return from(urlError: urlError)
        }
        if let authError = error as? SupabaseAuthError {
            return from(authError: authError)
        }
        if error is CancellationError {
            return .cancelled
        }
        return .unknown(message: error.localizedDescription)
    }

    public static func from(apiError: APIError) -> AppError {
        switch apiError {
        case .invalidURL, .missingTokenProvider:
            return .configuration
        case .unauthorized:
            return .unauthorized
        case .forbidden:
            return .forbidden
        case .notFound:
            return .notFound
        case let .validation(message):
            return .validation(message: message)
        case let .server(statusCode, message):
            if statusCode == 409 {
                return .conflict(message: message)
            } else if statusCode == 429 {
                return .rateLimited(retryAfter: nil)
            } else if statusCode == 422 {
                return .validation(message: message)
            } else {
                return .serverUnavailable(statusCode: statusCode)
            }
        case let .transport(message):
            return .connectionFailed
        case .invalidResponse:
            return .invalidResponse
        case let .decoding(details):
            return .decoding(details: details)
        }
    }

    public static func from(urlError: URLError) -> AppError {
        switch urlError.code {
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet, .networkConnectionLost:
            return .networkUnavailable
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .secureConnectionFailed, .serverCertificateHasBadDate,
             .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired, .cannotLoadFromNetwork:
            return .connectionFailed
        case .timedOut:
            return .timeout
        default:
            let nsError = urlError as NSError
            if nsError.domain == NSPOSIXErrorDomain && nsError.code == 61 {
                return .connectionFailed
            }
            return .connectionFailed
        }
    }

    public static func from(authError: SupabaseAuthError) -> AppError {
        switch authError {
        case .userCancelled:
            return .cancelled
        case .refreshFailed, .missingSession:
            return .unauthorized
        case .network:
            return .networkUnavailable
        case .configuration:
            return .configuration
        case let .decoding(details):
            return .decoding(details: details)
        case .invalidResponse:
            return .invalidResponse
        default:
            return .unknown(message: nil)
        }
    }

    public static func from(statusCode: Int, body: Data?, response: HTTPURLResponse? = nil) -> AppError {
        let message = body.flatMap { extractBackendDetail(from: $0) }

        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 409:
            return .conflict(message: message)
        case 422:
            return .validation(message: message)
        case 429:
            let retryAfter = response.flatMap { parseRetryAfter(from: $0) }
            return .rateLimited(retryAfter: retryAfter)
        case 400:
            return .validation(message: message)
        case 500...599:
            return .serverUnavailable(statusCode: statusCode)
        default:
            return .serverUnavailable(statusCode: statusCode)
        }
    }

    public static func extractBackendDetail(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? [String: Any], let detail = error["detail"] as? String {
            return detail
        }
        if let detail = object["detail"] as? String {
            return detail
        }
        if let details = object["detail"] as? [[String: Any]] {
            let messages = details.compactMap { $0["msg"] as? String }
            return messages.isEmpty ? nil : messages.joined(separator: "; ")
        }
        if let msg = object["msg"] as? String {
            return msg
        }
        if let message = object["message"] as? String {
            return message
        }
        return nil
    }

    public static func parseRetryAfter(from response: HTTPURLResponse) -> Int? {
        guard let rawValue = response.value(forHTTPHeaderField: "Retry-After") ?? response.value(forHTTPHeaderField: "retry-after") else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = Int(trimmed) {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: trimmed) {
            let delta = Int(date.timeIntervalSinceNow)
            return max(delta, 0)
        }
        return nil
    }
}
