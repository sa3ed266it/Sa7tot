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
                        serviceRow(title: "Altro", subtitle: "Inserisci un nome personalizzato", service: nil)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Servizi") {
                ForEach(services) { service in
                    Button {
                        selectedService = service
                        isCustom = false
                        customName = ""
                        dismiss()
                    } label: {
                        serviceRow(
                            title: service.displayName,
                            subtitle: service.categoryHint?.italianName ?? "Servizio",
                            service: service
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Scegli servizio")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Cerca un servizio")
    }

    private func serviceRow(title: String, subtitle: String, service: SubscriptionCatalogService?) -> some View {
        HStack(spacing: 12) {
            SubscriptionLogoView(service: service, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
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
    var italianName: String {
        switch self {
        case .streamingVideo: return "Video"
        case .musicAudio: return "Musica"
        case .cloudStorage: return "Archiviazione"
        case .productivity: return "Produttività"
        case .ai: return "Intelligenza artificiale"
        case .gaming: return "Giochi"
        case .fitnessWellness: return "Benessere"
        case .newsReading: return "Lettura"
        case .securityVPN: return "Sicurezza"
        case .developer: return "Sviluppo"
        case .deliveryMembership: return "Consegne"
        case .other: return "Servizio"
        }
    }
}
