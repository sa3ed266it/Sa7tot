import Foundation
import Security

public protocol SupabaseSessionStore: Sendable {
    func load() throws -> SupabaseAuthSession?
    func save(_ session: SupabaseAuthSession) throws
    func clear() throws
}

public final class KeychainSupabaseSessionStore: SupabaseSessionStore, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = "com.saied.sa7tot.supabase-auth",
        account: String = "session"
    ) {
        self.service = service
        self.account = account
    }

    public func load() throws -> SupabaseAuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SupabaseAuthError.keychainFailure(status) }
        guard let data = result as? Data else { throw SupabaseAuthError.invalidResponse }

        do {
            return try JSONDecoder().decode(SupabaseAuthSession.self, from: data)
        } catch {
            throw SupabaseAuthError.decoding("The saved auth session is invalid.")
        }
    }

    public func save(_ session: SupabaseAuthSession) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(session)
        } catch {
            throw SupabaseAuthError.decoding("The auth session could not be encoded.")
        }

        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SupabaseAuthError.keychainFailure(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw SupabaseAuthError.keychainFailure(addStatus) }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SupabaseAuthError.keychainFailure(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
