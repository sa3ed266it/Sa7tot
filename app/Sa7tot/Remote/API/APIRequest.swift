import Foundation

public enum APIHTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public enum APIAuthentication: Sendable {
    case `public`
    case required
}

public struct APIRequest<Response: Decodable>: Sendable {
    public let method: APIHTTPMethod
    public let path: String
    public let queryItems: [URLQueryItem]
    public let body: Data?
    public let authentication: APIAuthentication

    public init(
        method: APIHTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        authentication: APIAuthentication = .required
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
        self.authentication = authentication
    }

    public init<Body: Encodable>(
        method: APIHTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        authentication: APIAuthentication = .required,
        encoder: JSONEncoder = RemoteJSON.encoder()
    ) throws {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = try encoder.encode(body)
        self.authentication = authentication
    }
}
