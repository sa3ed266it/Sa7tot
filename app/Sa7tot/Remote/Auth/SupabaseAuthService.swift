import Combine
import Foundation
import OSLog

private let authValidationLogger = Logger(subsystem: "com.saied.sa7tot", category: "AuthValidation")

@MainActor
public final class SupabaseAuthService: ObservableObject {
    @Published public private(set) var state: SupabaseAuthState

    private let coordinator: SupabaseAuthSessionCoordinator?

    public init(coordinator: SupabaseAuthSessionCoordinator) {
        self.coordinator = coordinator
        self.state = .restoring
    }

    public init(
        configuration: SupabaseAuthConfiguration?,
        store: SupabaseSessionStore = KeychainSupabaseSessionStore(),
        session: URLSession = .shared
    ) {
        if let configuration {
            let client = SupabaseAuthClient(configuration: configuration, session: session)
            self.coordinator = SupabaseAuthSessionCoordinator(client: client, store: store)
            self.state = .restoring
        } else {
            self.coordinator = nil
            self.state = .error(.configuration)
        }
    }

    public static func current(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SupabaseAuthService {
        do {
            return SupabaseAuthService(
                configuration: try SupabaseAuthConfiguration.current(bundle: bundle, environment: environment)
            )
        } catch let error as SupabaseAuthConfigurationError {
            _ = error
            return SupabaseAuthService(configuration: nil)
        } catch {
            return SupabaseAuthService(configuration: nil)
        }
    }

    public var tokenProvider: AuthTokenProvider? { coordinator }

    public func restoreSession() async {
        guard let coordinator else {
            state = .error(.configuration)
            return
        }

        state = .restoring
        do {
            if let session = try await coordinator.restore() {
                guard !Task.isCancelled else { return }
                state = .signedIn(session)
            } else {
                guard !Task.isCancelled else { return }
                state = .signedOut
            }
        } catch let error as SupabaseAuthError {
            guard !Task.isCancelled else { return }
            state = .error(Self.presentationError(for: error))
        } catch {
            guard !Task.isCancelled else { return }
            state = .error(.unknown)
        }
    }

    public func signIn(with credential: AppleAuthorizationCredential) async {
        guard let coordinator else {
            state = .error(.configuration)
            return
        }

        state = .restoring
        do {
            let session = try await coordinator.signIn(with: credential)
            state = .signedIn(session)
        } catch let error as SupabaseAuthError {
            if case .userCancelled = error {
                state = .signedOut
            } else {
                state = .error(Self.presentationError(for: error))
            }
        } catch {
            state = .error(.unknown)
        }
    }

    public func signOut() async {
        guard let coordinator else {
            state = .signedOut
            return
        }

        do {
            try await coordinator.signOut()
            state = .signedOut
        } catch let error as SupabaseAuthError {
            // Local credentials were cleared before the remote logout call.
            state = .error(Self.presentationError(for: error))
        } catch {
            state = .error(.unknown)
        }
    }

    public func handle(error: SupabaseAuthError) {
        if case .userCancelled = error {
            state = .signedOut
        } else {
            state = .error(Self.presentationError(for: error))
        }
    }

#if DEBUG
    /// Runs the real authenticated bootstrap path without changing any production data flow.
    /// The result is intentionally reduced to validation metadata; tokens and response payloads
    /// are never logged.
    public func runBootstrapSmokeTest() async {
        guard let coordinator, case .signedIn = state else { return }

        do {
            let configuration = try APIConfiguration.current()
            let client = APIClient(configuration: configuration, tokenProvider: coordinator)
            let bootstrap = try await RemoteBootstrapRepository(client: client).load()
            let session = try await coordinator.restore()
            let subjectMatchesProfile = session?.userID == bootstrap.profile.userID
            let message = "Authenticated bootstrap succeeded: profile_subject_matches_session=\(subjectMatchesProfile) accounts=\(bootstrap.accounts.count) categories=\(bootstrap.categories.count)"
            authValidationLogger.info("\(message, privacy: .public)")
            print("[AuthValidation] \(message)")
        } catch let error as APIError {
            let message = "Authenticated bootstrap failed: api_error=\(String(describing: error))"
            authValidationLogger.error("\(message, privacy: .public)")
            print("[AuthValidation] \(message)")
        } catch {
            let message = "Authenticated bootstrap failed: error_type=\(String(describing: type(of: error)))"
            authValidationLogger.error("\(message, privacy: .public)")
            print("[AuthValidation] \(message)")
        }
    }
#endif

    public static func presentationError(for error: SupabaseAuthError) -> SupabaseAuthPresentationError {
        switch error {
        case .configuration:
            return .configuration
        case .network:
            return .network
        case .missingIdentityToken, .invalidAppleCredential, .userCancelled:
            return .credential
        case .exchangeFailed:
            return .exchange
        case .refreshFailed:
            return .refresh
        case .signOutFailed, .missingSession, .keychainFailure, .decoding, .invalidResponse:
            return .unknown
        }
    }
}
