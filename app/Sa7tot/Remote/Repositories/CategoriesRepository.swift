import Foundation

public struct RemoteCategoriesRepository: Sendable {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func list() async throws -> [RemoteCategoryDTO] {
        try await client.get([RemoteCategoryDTO].self, path: "/v1/categories")
    }

    public func create(_ payload: RemoteCategoryCreatePayload) async throws -> RemoteCategoryDTO {
        try await client.post(RemoteCategoryDTO.self, path: "/v1/categories", body: payload)
    }

    public func update(categoryID: UUID, _ payload: RemoteCategoryUpdatePayload) async throws -> RemoteCategoryDTO {
        try await client.patch(RemoteCategoryDTO.self, path: "/v1/categories/\(categoryID.uuidString)", body: payload)
    }

    public func delete(categoryID: UUID) async throws -> RemoteCategoryDTO {
        try await client.delete(RemoteCategoryDTO.self, path: "/v1/categories/\(categoryID.uuidString)")
    }
}
