import Foundation
import Combine
import UIKit
import UserNotifications

public enum PushTokenCoordinatorNotifications {
    public static let didRegister = Notification.Name("Sa7totAPNsDeviceTokenDidRegister")
    public static let didFailToRegister = Notification.Name("Sa7totAPNsRegistrationDidFail")
}

@MainActor
public final class PushTokenCoordinator: ObservableObject {
    private let client: APIClient?
    private let tokenProvider: AuthTokenProvider?
    private let environment: RemotePushEnvironment
    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private var observerTokens: [NSObjectProtocol] = []
    private var registrationTask: Task<Void, Never>?
    private var registeredKey: String?
    private var previousToken: String?
    private var authenticatedUserID: UUID?

    private static let storedTokenKey = "push.apnsToken"

    @Published public private(set) var apnsToken: String?
    @Published public private(set) var lastRegistrationError: String?

    public init(
        client: APIClient?,
        tokenProvider: AuthTokenProvider?,
        environment: RemotePushEnvironment = .current,
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.environment = environment
        self.center = center
        self.defaults = defaults
        let storedToken = defaults.string(forKey: Self.storedTokenKey)
        self.apnsToken = storedToken
        self.previousToken = storedToken
    }

    deinit {
        observerTokens.forEach(NotificationCenter.default.removeObserver)
        registrationTask?.cancel()
    }

    public func start() {
        guard observerTokens.isEmpty else { return }

        let notificationCenter = NotificationCenter.default
        observerTokens.append(
            notificationCenter.addObserver(
                forName: PushTokenCoordinatorNotifications.didRegister,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let tokenData = notification.object as? Data else { return }
                Task { @MainActor [weak self] in
                    self?.receive(deviceTokenData: tokenData)
                }
            }
        )
        observerTokens.append(
            notificationCenter.addObserver(
                forName: PushTokenCoordinatorNotifications.didFailToRegister,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.lastRegistrationError = (notification.object as? Error).map(String.init(describing:))
                }
            }
        )
    }

    public func reconcile(authState: SupabaseAuthState) {
        switch authState {
        case let .signedIn(session):
            authenticatedUserID = session.userID
            registerIfAuthorized()
            uploadIfReady()
        case .signedOut, .error:
            authenticatedUserID = nil
            registeredKey = nil
            registrationTask?.cancel()
            registrationTask = nil
        case .restoring:
            break
        }
    }

    public func registerIfAuthorized() {
        center.getNotificationSettings { [weak self] settings in
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
            Task { @MainActor in
                UIApplication.shared.registerForRemoteNotifications()
                self?.uploadIfReady()
            }
        }
    }

    public func deactivateCurrentRegistration() async throws {
        guard let token = apnsToken, authenticatedUserID != nil else {
            authenticatedUserID = nil
            registeredKey = nil
            return
        }

        guard let client, tokenProvider != nil else {
            throw AppError.configuration
        }

        registrationTask?.cancel()
        registrationTask = nil
        _ = try await RemotePushDevicesRepository(client: client).deactivate(token: token)
        authenticatedUserID = nil
        registeredKey = nil
    }

    public static func hexadecimalToken(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func receive(deviceTokenData: Data) {
        let token = Self.hexadecimalToken(from: deviceTokenData)
        if token != apnsToken {
            previousToken = defaults.string(forKey: Self.storedTokenKey)
            defaults.set(token, forKey: Self.storedTokenKey)
        }
        apnsToken = token
        lastRegistrationError = nil
        uploadIfReady()
    }

    private func uploadIfReady() {
        guard let token = apnsToken,
              let userID = authenticatedUserID,
              let client,
              tokenProvider != nil else { return }

        let key = "\(userID.uuidString.lowercased()):\(environment.rawValue):\(token)"
        guard registeredKey != key, registrationTask == nil else { return }
        registeredKey = key
        let repository = RemotePushDevicesRepository(client: client)
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let previousToken = previousToken

        registrationTask = Task { [weak self] in
            do {
                if let previousToken, previousToken != token {
                    _ = try? await repository.deactivate(token: previousToken)
                }
                _ = try await repository.register(token: token, environment: environment, appVersion: appVersion)
                guard !Task.isCancelled else { return }
                self?.registrationTask = nil
                self?.previousToken = nil
                self?.lastRegistrationError = nil
            } catch {
                guard !Task.isCancelled else { return }
                self?.registeredKey = nil
                self?.registrationTask = nil
                self?.lastRegistrationError = String(describing: error)
            }
        }
    }
}

@MainActor
public enum PushSignOutLifecycle {
    @discardableResult
    public static func run(
        deactivate: () async throws -> Void,
        signOut: () async -> Void
    ) async -> Bool {
        do {
            try await deactivate()
            await signOut()
            return true
        } catch {
            return false
        }
    }
}

extension RemotePushEnvironment {
    public static var current: Self {
        let value = (Bundle.main.object(forInfoDictionaryKey: "APNS_ENVIRONMENT") as? String)?.lowercased()
        return Self(rawValue: value ?? "development") ?? .development
    }
}
