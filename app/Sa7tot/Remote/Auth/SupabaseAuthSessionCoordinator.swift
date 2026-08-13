import Foundation

public actor SupabaseAuthSessionCoordinator: AuthTokenProvider {
    private let client: SupabaseAuthClientProtocol
    private let store: SupabaseSessionStore
    private var session: SupabaseAuthSession?
    private var refreshTask: Task<SupabaseAuthSession, Error>?

    public init(client: SupabaseAuthClientProtocol, store: SupabaseSessionStore) {
        self.client = client
        self.store = store
    }

    public func restore() async throws -> SupabaseAuthSession? {
        if let session { return session }
        let stored: SupabaseAuthSession?
        do {
            stored = try store.load()
        } catch let error as SupabaseAuthError where Self.isRecoverableLocalSessionError(error) {
            try? store.clear()
            return nil
        }
        guard let stored else { return nil }
        if stored.isValid() {
            session = stored
            return stored
        }
        let refreshed: SupabaseAuthSession
        do {
            refreshed = try await refresh(stored)
        } catch let error as SupabaseAuthError where Self.isRecoverableLocalSessionError(error) {
            try? store.clear()
            return nil
        }
        session = refreshed
        return refreshed
    }

    public func signIn(with credential: AppleAuthorizationCredential) async throws -> SupabaseAuthSession {
        let newSession = try await client.exchangeAppleCredential(credential)
        try store.save(newSession)
        session = newSession
        return newSession
    }

    public func accessToken() async throws -> String {
        if session == nil {
            _ = try await restore()
        }
        guard let session else { throw SupabaseAuthError.missingSession }
        if session.isValid() { return session.accessToken }
        return try await refresh(session).accessToken
    }

    public func refreshSession() async throws -> String {
        if let session {
            let refreshed = try await refresh(session)
            return refreshed.accessToken
        }
        if let restored = try await restore() {
            return restored.accessToken
        }
        throw SupabaseAuthError.missingSession
    }

    public func signOut() async throws {
        let oldSession = session
        session = nil
        refreshTask?.cancel()
        refreshTask = nil
        try store.clear()
        if let oldSession {
            try await client.signOut(accessToken: oldSession.accessToken)
        }
    }

    private func refresh(_ oldSession: SupabaseAuthSession) async throws -> SupabaseAuthSession {
        if let refreshTask {
            return try await refreshTask.value
        }

        let client = self.client
        let store = self.store
        let task = Task {
            let refreshed = try await client.refreshSession(refreshToken: oldSession.refreshToken)
            try store.save(refreshed)
            return refreshed
        }
        refreshTask = task

        do {
            let refreshed = try await task.value
            session = refreshed
            refreshTask = nil
            return refreshed
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private static func isRecoverableLocalSessionError(_ error: SupabaseAuthError) -> Bool {
        switch error {
        case .decoding, .invalidResponse, .keychainFailure:
            return true
        default:
            return false
        }
    }
}
