import Foundation

public struct AppErrorPresentation: Equatable, Sendable {
    public let iconName: String
    public let titleKey: String
    public let messageKey: String
    public let primaryActionKey: String

    public init(
        iconName: String,
        titleKey: String,
        messageKey: String,
        primaryActionKey: String = "action.retry"
    ) {
        self.iconName = iconName
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.primaryActionKey = primaryActionKey
    }
}

public enum AppErrorPresentationPolicy {
    public static func blockingPresentation(for error: AppError) -> AppErrorPresentation {
        switch error {
        case .networkUnavailable:
            return AppErrorPresentation(
                iconName: "wifi.slash",
                titleKey: "error.blocking.offline.title",
                messageKey: "error.blocking.offline.message"
            )
        case .connectionFailed:
            return AppErrorPresentation(
                iconName: "exclamationmark.arrow.triangle.2.circlepath",
                titleKey: "error.blocking.connection.title",
                messageKey: "error.blocking.connection.message"
            )
        case .timeout:
            return AppErrorPresentation(
                iconName: "clock.badge.exclamationmark",
                titleKey: "error.blocking.timeout.title",
                messageKey: "error.blocking.timeout.message"
            )
        case .serverUnavailable:
            return AppErrorPresentation(
                iconName: "server.rack",
                titleKey: "error.blocking.server.title",
                messageKey: "error.blocking.server.message"
            )
        case .decoding, .invalidResponse, .notFound:
            return AppErrorPresentation(
                iconName: "exclamationmark.triangle",
                titleKey: "error.blocking.invalidResponse.title",
                messageKey: "error.blocking.invalidResponse.message"
            )
        case .forbidden:
            return AppErrorPresentation(
                iconName: "lock.slash",
                titleKey: "error.blocking.forbidden.title",
                messageKey: "error.blocking.forbidden.message"
            )
        case .unauthorized, .rateLimited, .conflict, .validation, .configuration, .cancelled, .unknown:
            return AppErrorPresentation(
                iconName: "exclamationmark.triangle",
                titleKey: "error.blocking.generic.title",
                messageKey: "error.blocking.generic.message"
            )
        }
    }
}
