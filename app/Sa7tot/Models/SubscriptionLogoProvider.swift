import Foundation

enum SubscriptionLogoSource: Equatable, Sendable {
    case appIcon(assetName: String)
    case brandAsset(assetName: String)
    case simpleIcon(assetName: String, brandHex: String?)
    case systemFallback(String)
}

protocol SubscriptionLogoProviding {
    func logoSource(for service: SubscriptionCatalogService) -> SubscriptionLogoSource
}

struct LocalSubscriptionLogoProvider: SubscriptionLogoProviding {
    static let defaultFallbackSystemName = "repeat.circle.fill"

    let fallbackSystemName: String

    init(fallbackSystemName: String = Self.defaultFallbackSystemName) {
        self.fallbackSystemName = fallbackSystemName
    }

    func logoSource(for service: SubscriptionCatalogService) -> SubscriptionLogoSource {
        SubscriptionLogoMetadata.sourcesByServiceID[service.id]
            ?? .systemFallback(fallbackSystemName)
    }

    func simpleIconFallback(for service: SubscriptionCatalogService) -> SubscriptionLogoSource? {
        SubscriptionLogoMetadata.simpleIconFallbacksByServiceID[service.id]
    }
}
