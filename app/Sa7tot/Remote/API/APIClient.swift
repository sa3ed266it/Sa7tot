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
        try await sendInternal(request, allowAuthRetry: true)
    }

    private func sendInternal<Response: Decodable>(_ request: APIRequest<Response>, allowAuthRetry: Bool) async throws -> Response {
        try Task.checkCancellation()

        let url: URL
        do {
            url = try configuration.url(path: request.path, queryItems: request.queryItems)
        } catch {
            throw AppError.configuration
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
                throw AppError.configuration
            }
            let token: String
            do {
                token = try await tokenProvider.accessToken()
            } catch {
                let mapped = AppError.from(error)
                switch mapped {
                case .networkUnavailable, .connectionFailed, .timeout:
                    throw mapped
                default:
                    throw AppError.unauthorized
                }
            }
            guard !token.isEmpty else {
                throw AppError.unauthorized
            }
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)

            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppError.invalidResponse
            }

            if httpResponse.statusCode == 401, request.authentication == .required, allowAuthRetry, let tokenProvider {
                let newToken: String
                do {
                    newToken = try await tokenProvider.refreshSession()
                } catch {
                    let mapped = AppError.from(error)
                    switch mapped {
                    case .networkUnavailable, .connectionFailed, .timeout:
                        throw mapped
                    default:
                        throw AppError.unauthorized
                    }
                }

                guard !newToken.isEmpty else {
                    throw AppError.unauthorized
                }

                var retryUrlRequest = urlRequest
                retryUrlRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")

                let (retryData, retryResponse) = try await session.data(for: retryUrlRequest)
                try Task.checkCancellation()

                guard let retryHttpResponse = retryResponse as? HTTPURLResponse else {
                    throw AppError.invalidResponse
                }

                guard (200..<300).contains(retryHttpResponse.statusCode) else {
                    throw AppError.from(statusCode: retryHttpResponse.statusCode, body: retryData, response: retryHttpResponse)
                }

                if Response.self == EmptyResponse.self, retryData.isEmpty {
                    return EmptyResponse() as! Response
                }

                do {
                    return try decoder.decode(Response.self, from: retryData)
                } catch {
                    throw AppError.decoding(details: error.localizedDescription)
                }
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AppError.from(statusCode: httpResponse.statusCode, body: data, response: httpResponse)
            }

            if Response.self == EmptyResponse.self, data.isEmpty {
                return EmptyResponse() as! Response
            }

            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw AppError.decoding(details: error.localizedDescription)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as AppError {
            throw error
        } catch let error as URLError {
            throw AppError.from(urlError: error)
        } catch {
            throw AppError.unknown(message: error.localizedDescription)
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
}

public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}
