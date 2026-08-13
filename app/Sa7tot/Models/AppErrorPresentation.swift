import Foundation
import SwiftUI

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

public struct InlineMutationErrorView: View {
    public let error: AppError
    public let titleKey: String?
    public let onDismiss: (() -> Void)?

    public init(error: AppError, titleKey: String? = "error.mutation.save.title", onDismiss: (() -> Void)? = nil) {
        self.error = error
        self.titleKey = titleKey
        self.onDismiss = onDismiss
    }

    private var presentation: AppErrorPresentation {
        AppErrorPresentationPolicy.blockingPresentation(for: error)
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: presentation.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.orange)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(titleKey ?? presentation.titleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)

                Text(LocalizedStringKey(presentation.messageKey))
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.key("action.dismiss"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .padding(.horizontal, 20)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
