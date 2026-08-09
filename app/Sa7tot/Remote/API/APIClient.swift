import Foundation

public final class APIClient: @unchecked Sendable {
    private let configuration: APIConfiguration
    private let session: URLSession
    private let tokenProvider: AuthTokenProvider?
    private let decoder: JSONDecoder

    public init(
        configuration: APIConfiguration,
        session: URLSession = .shared,
        tokenProvider: AuthTokenProvider? = nil,
        decoder: JSONDecoder = RemoteJSON.decoder()
    ) {
        self.configuration = configuration
        self.session = session
        self.tokenProvider = tokenProvider
        self.decoder = decoder
    }

    public func send<Response: Decodable>(_ request: APIRequest<Response>) async throws -> Response {
        try Task.checkCancellation()


        let url: URL
        do {
            url = try configuration.url(path: request.path, queryItems: request.queryItems)
        } catch let error as APIConfigurationError {
            throw APIError.invalidURL(String(describing: error))
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = request.body
        }

        if request.authentication == .required {
            guard let tokenProvider else {
                throw APIError.missingTokenProvider
            }
            let token = try await tokenProvider.accessToken()
            guard !token.isEmpty else {
                throw APIError.unauthorized("The access token provider returned an empty token.")
            }
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)

            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw apiError(statusCode: httpResponse.statusCode, body: data)
            }

            if Response.self == EmptyResponse.self, data.isEmpty {
                return EmptyResponse() as! Response
            }

            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw APIError.decoding(error.localizedDescription)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    public func get<Response: Decodable>(
        _ responseType: Response.Type,
        path: String,
        queryItems: [URLQueryItem] = [],
        authentication: APIAuthentication = .required
    ) async throws -> Response {
        try await send(
            APIRequest<Response>(
                method: .get,
                path: path,
                queryItems: queryItems,
                authentication: authentication
            )
        )
    }

    public func post<Response: Decodable, Body: Encodable>(
        _ responseType: Response.Type,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        authentication: APIAuthentication = .required
    ) async throws -> Response {
        try await send(
            try APIRequest<Response>(
                method: .post,
                path: path,
                queryItems: queryItems,
                body: body,
                authentication: authentication
            )
        )
    }

    public func patch<Response: Decodable, Body: Encodable>(
        _ responseType: Response.Type,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        authentication: APIAuthentication = .required
    ) async throws -> Response {
        try await send(
            try APIRequest<Response>(
                method: .patch,
                path: path,
                queryItems: queryItems,
                body: body,
                authentication: authentication
            )
        )
    }

    public func put<Response: Decodable, Body: Encodable>(
        _ responseType: Response.Type,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        authentication: APIAuthentication = .required
    ) async throws -> Response {
        try await send(
            try APIRequest<Response>(
                method: .put,
                path: path,
                queryItems: queryItems,
                body: body,
                authentication: authentication
            )
        )
    }

    public func delete<Response: Decodable>(
        _ responseType: Response.Type,
        path: String,
        queryItems: [URLQueryItem] = [],
        authentication: APIAuthentication = .required
    ) async throws -> Response {
        try await send(
            APIRequest<Response>(
                method: .delete,
                path: path,
                queryItems: queryItems,
                authentication: authentication
            )
        )
    }

    private func apiError(statusCode: Int, body: Data) -> APIError {
        let message = Self.serverMessage(from: body)
        switch statusCode {
        case 401: return .unauthorized(message)
        case 403: return .forbidden(message)
        case 404: return .notFound(message)
        case 422: return .validation(message)
        default: return .server(statusCode: statusCode, message: message)
        }
    }

    private static func serverMessage(from data: Data) -> String? {
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
        return nil
    }
}

public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}
