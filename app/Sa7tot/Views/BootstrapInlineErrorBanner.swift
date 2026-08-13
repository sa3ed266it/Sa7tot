import SwiftUI

struct BootstrapInlineErrorBanner: View {
    let error: AppError
    let retry: () -> Void

    @State private var isRetrying = false

    private var presentation: AppErrorPresentation {
        AppErrorPresentationPolicy.blockingPresentation(for: error)
    }

    var body: some View {
        HStack(spacing: 12) {
            // SF Symbol Icon
            Image(systemName: presentation.iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            // Text Hierarchy (Title & Message)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(presentation.titleKey))
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.primary)

                Text(LocalizedStringKey(presentation.messageKey))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if #available(iOS 26.0, *) {
                Button {
                    handleRetryTap()
                } label: {
                    retryButtonLabel
                }
                .buttonStyle(.glass)
                .disabled(isRetrying)
                .accessibilityLabel(Text(LocalizedStringKey(presentation.primaryActionKey)))
            } else {
                Button {
                    handleRetryTap()
                } label: {
                    retryButtonLabel
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRetrying)
                .accessibilityLabel(Text(LocalizedStringKey(presentation.primaryActionKey)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .padding(.horizontal, 16)
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private var retryButtonLabel: some View {
        HStack(spacing: 6) {
            if isRetrying {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            Text(LocalizedStringKey(presentation.primaryActionKey))
                .font(.subheadline)
                .bold()
        }
        .padding(.horizontal, 4)
    }

    private func handleRetryTap() {
        guard !isRetrying else { return }
        isRetrying = true
        retry()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isRetrying = false
        }
    }
}
