import UIKit
import SwiftUI

struct SubscriptionLogoView: View {
    let service: SubscriptionCatalogService?
    let size: CGFloat

    private let provider = LocalSubscriptionLogoProvider()

    var body: some View {
        Group {
            if let service {
                renderedLogo(for: service)
            } else {
                Image(systemName: LocalSubscriptionLogoProvider.defaultFallbackSystemName)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func renderedLogo(for service: SubscriptionCatalogService) -> some View {
        let source = provider.logoSource(for: service)
        switch source {
        case let .appIcon(assetName):
            if UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                fallbackLogo(for: service)
            }
        case let .brandAsset(assetName):
            if UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                fallbackLogo(for: service)
            }
        case let .simpleIcon(assetName, _):
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(2)
        case let .systemFallback(systemName):
            Image(systemName: systemName)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func fallbackLogo(for service: SubscriptionCatalogService) -> some View {
        if let fallback = provider.simpleIconFallback(for: service) {
            renderedFallback(fallback)
        } else {
            Image(systemName: LocalSubscriptionLogoProvider.defaultFallbackSystemName)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func renderedFallback(_ source: SubscriptionLogoSource) -> some View {
        switch source {
        case let .simpleIcon(assetName, _):
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(2)
        case let .systemFallback(systemName):
            Image(systemName: systemName)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.secondary)
        case let .brandAsset(assetName):
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .appIcon:
            Image(systemName: LocalSubscriptionLogoProvider.defaultFallbackSystemName)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct SubscriptionServicePickerView: View {
    @Binding var selectedService: SubscriptionCatalogService?
    @Binding var isCustom: Bool
    @Binding var customName: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var services: [SubscriptionCatalogService] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = query.isEmpty
            ? SubscriptionServiceCatalog.all.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            : SubscriptionServiceCatalog.search(query)
        return result
    }

    var body: some View {
        List {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    Button {
                        selectedService = nil
                        isCustom = true
                        customName = ""
                        dismiss()
                    } label: {
                        serviceRow(title: AppLocalization.string("subscription.other"), subtitle: AppLocalization.string("subscription.customName"), service: nil)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section(AppLocalization.key("subscription.services")) {
                ForEach(services) { service in
                    Button {
                        selectedService = service
                        isCustom = false
                        customName = ""
                        dismiss()
                    } label: {
                        serviceRow(
                            title: service.displayName,
                            subtitle: service.categoryHint?.localizedTitle ?? AppLocalization.string("common.service"),
                            service: service
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(AppLocalization.key("subscription.chooseService"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: AppLocalization.key("subscription.searchService"))
    }

    private func serviceRow(title: String, subtitle: String, service: SubscriptionCatalogService?) -> some View {
        HStack(spacing: 12) {
            SubscriptionLogoView(service: service, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

private extension SubscriptionServiceCategory {
    var localizedTitle: String {
        switch self {
        case .streamingVideo: return AppLocalization.string("subscription.category.video")
        case .musicAudio: return AppLocalization.string("subscription.category.music")
        case .cloudStorage: return AppLocalization.string("subscription.category.cloud")
        case .productivity: return AppLocalization.string("subscription.category.productivity")
        case .ai: return AppLocalization.string("subscription.category.ai")
        case .gaming: return AppLocalization.string("subscription.category.gaming")
        case .fitnessWellness: return AppLocalization.string("subscription.category.fitness")
        case .newsReading: return AppLocalization.string("subscription.category.reading")
        case .securityVPN: return AppLocalization.string("subscription.category.security")
        case .developer: return AppLocalization.string("subscription.category.developer")
        case .deliveryMembership: return AppLocalization.string("subscription.category.delivery")
        case .other: return AppLocalization.string("common.service")
        }
    }
}
