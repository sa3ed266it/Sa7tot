import Foundation
import XCTest

final class SubscriptionCatalogTests: XCTestCase {
    func testCatalogHasUniqueNormalizedEntries() {
        XCTAssertGreaterThanOrEqual(SubscriptionServiceCatalog.all.count, 57)

        let ids = SubscriptionServiceCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)

        for service in SubscriptionServiceCatalog.all {
            XCTAssertFalse(service.id.isEmpty)
            XCTAssertEqual(service.id, SubscriptionCatalogNormalizer.serviceID(service.id))
            XCTAssertFalse(service.displayName.isEmpty)
            XCTAssertFalse(service.domain.isEmpty)
            XCTAssertFalse(service.domain.contains("://"))
            XCTAssertFalse(service.domain.contains("/"))
            XCTAssertEqual(SubscriptionCatalogNormalizer.domain(service.domain), service.domain)
        }
    }

    func testRequiredServicesResolveToStableIdentities() {
        let requiredIDs = [
            "netflix", "spotify", "chatgpt", "icloud-plus", "youtube-premium", "disney-plus",
            "google-one", "microsoft-365", "adobe-creative-cloud", "playstation-plus",
            "xbox-game-pass", "nintendo-switch-online", "dazn"
        ]

        for id in requiredIDs {
            let service = SubscriptionServiceCatalog.service(forID: id)
            XCTAssertNotNil(service, "Missing catalog service \(id)")
            XCTAssertEqual(service?.id, id)
            XCTAssertFalse(service?.domain.isEmpty ?? true)
        }
    }

    func testCatalogSearchHandlesAliasesWhitespaceAndCase() {
        XCTAssertEqual(SubscriptionServiceCatalog.search("Netflix").first?.id, "netflix")
        XCTAssertEqual(SubscriptionServiceCatalog.search("net").first?.id, "netflix")
        XCTAssertEqual(SubscriptionServiceCatalog.search("spotify").first?.id, "spotify")
        XCTAssertEqual(SubscriptionServiceCatalog.search("chat gpt").first?.id, "chatgpt")
        XCTAssertEqual(SubscriptionServiceCatalog.search("icloud").first?.id, "icloud-plus")
        XCTAssertEqual(SubscriptionServiceCatalog.search("yt premium").first?.id, "youtube-premium")
        XCTAssertEqual(SubscriptionServiceCatalog.search("youtube").first?.id, "youtube-premium")
        XCTAssertEqual(SubscriptionServiceCatalog.search("ps plus").first?.id, "playstation-plus")
        XCTAssertEqual(SubscriptionServiceCatalog.search("game pass").first?.id, "xbox-game-pass")
        XCTAssertEqual(SubscriptionServiceCatalog.search("office").first?.id, "microsoft-365")
        XCTAssertEqual(SubscriptionServiceCatalog.search("adobe").first?.id, "adobe-creative-cloud")
        XCTAssertEqual(SubscriptionServiceCatalog.search("  Caffè  ").isEmpty, true)
    }

    func testCatalogDomainNormalizationRemovesSchemeWWWAndPath() {
        XCTAssertEqual(
            SubscriptionCatalogNormalizer.domain("https://WWW.Example.com/path/to/logo"),
            "example.com"
        )
        XCTAssertEqual(SubscriptionCatalogNormalizer.domain("http://www.spotify.com/"), "spotify.com")
    }

    func testMappedServiceUsesBundledAsset() {
        let service = SubscriptionServiceCatalog.service(forID: "netflix")!
        let source = LocalSubscriptionLogoProvider().logoSource(for: service)

        XCTAssertEqual(source, .appIcon(assetName: "subscription-app-icon-netflix"))
    }

    func testFullColorSourcesWinOverSimpleIconFallbacks() {
        let provider = LocalSubscriptionLogoProvider()
        for id in ["netflix", "spotify", "chatgpt", "disney-plus", "microsoft-365", "canva", "slack"] {
            let service = SubscriptionServiceCatalog.service(forID: id)!
            guard case .appIcon = provider.logoSource(for: service) else {
                return XCTFail("Expected full-color App Store source for \(id)")
            }
        }
        guard case .brandAsset = provider.logoSource(for: SubscriptionServiceCatalog.service(forID: "xbox-game-pass")!) else {
            return XCTFail("Expected full-color official product source for Xbox Game Pass")
        }
        guard case .brandAsset = provider.logoSource(for: SubscriptionServiceCatalog.service(forID: "icloud-plus")!) else {
            return XCTFail("Expected full-color official product source for iCloud+")
        }
        XCTAssertEqual(
            provider.simpleIconFallback(for: SubscriptionServiceCatalog.service(forID: "icloud-plus")!),
            .simpleIcon(assetName: "subscription-logo-icloud-plus", brandHex: "3693F3")
        )
        XCTAssertNotNil(provider.simpleIconFallback(for: SubscriptionServiceCatalog.service(forID: "netflix")!))
        XCTAssertNil(provider.simpleIconFallback(for: SubscriptionServiceCatalog.service(forID: "chatgpt")!))
    }

    func testSubscriptionCreationModesKeepSubscriptionOutOfTransactionTypes() {
        XCTAssertEqual(AddEntryMode.allCases, [.expense, .income, .subscription])
        XCTAssertNotEqual(AddEntryMode.subscription.rawValue, "expense")
        XCTAssertNotEqual(AddEntryMode.subscription.rawValue, "income")
    }

    func testSubscriptionStartDateDerivesUpcomingRenewalsByLocalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 8)))
        let past = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 8)))
        let future = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 8)))

        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: SubscriptionDateNormalization.nextRenewal(cadence: .monthly, startDate: past, from: today, calendar: calendar)),
            DateComponents(year: 2026, month: 9, day: 8)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: SubscriptionDateNormalization.nextRenewal(cadence: .monthly, startDate: today, from: today, calendar: calendar)),
            DateComponents(year: 2026, month: 9, day: 8)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: SubscriptionDateNormalization.nextRenewal(cadence: .monthly, startDate: future, from: today, calendar: calendar)),
            DateComponents(year: 2026, month: 8, day: 20)
        )
        XCTAssertEqual(calendar.component(.hour, from: SubscriptionDateNormalization.localNoon(past, calendar: calendar)), 12)
    }

    func testSubscriptionStartDateDerivesWeeklyAndYearlyRenewals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 8)))
        let weeklyStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 8)))
        let yearlyStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 8, day: 8, hour: 8)))

        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: SubscriptionDateNormalization.nextRenewal(cadence: .weekly, startDate: weeklyStart, from: today, calendar: calendar)),
            DateComponents(year: 2026, month: 8, day: 15)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: SubscriptionDateNormalization.nextRenewal(cadence: .yearly, startDate: yearlyStart, from: today, calendar: calendar)),
            DateComponents(year: 2027, month: 8, day: 8)
        )
    }

    func testSubscriptionStartDatePreservesEndOfMonthAnchor() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 8)))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 8)))

        let next = SubscriptionDateNormalization.nextRenewal(cadence: .monthly, startDate: start, from: today, calendar: calendar)

        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: next), DateComponents(year: 2026, month: 3, day: 31))
    }

    func testKnownServiceAndFallbackLogoResolutionForCreationPicker() {
        let provider = LocalSubscriptionLogoProvider()
        for id in ["netflix", "spotify", "adobe-creative-cloud", "xbox-game-pass"] {
            let service = SubscriptionServiceCatalog.service(forID: id)!
            switch id {
            case "adobe-creative-cloud", "xbox-game-pass":
                guard case .brandAsset = provider.logoSource(for: service) else {
                    return XCTFail("Expected official product asset for \(id)")
                }
            default:
                guard case .appIcon = provider.logoSource(for: service) else {
                    return XCTFail("Expected App Store asset for \(id)")
                }
            }
        }

        let chatGPT = SubscriptionServiceCatalog.service(forID: "chatgpt")!
        XCTAssertEqual(provider.logoSource(for: chatGPT), .appIcon(assetName: "subscription-app-icon-chatgpt"))
    }

    func testUnresolvedServiceUsesSystemFallback() {
        let service = SubscriptionCatalogService(
            id: "historical-service",
            displayName: "Historical Service",
            domain: "example.com"
        )!
        let source = LocalSubscriptionLogoProvider().logoSource(for: service)

        XCTAssertEqual(source, .systemFallback("repeat.circle.fill"))
    }

    func testRemovedServiceIDsRemainUnknownAndUseGenericFallback() {
        let removedIDs = [
            "ea-play", "ubisoft-plus", "nvidia-geforce-now", "apple-arcade",
            "strava", "midjourney", "jetbrains-all-products", "freeletics"
        ]
        let provider = LocalSubscriptionLogoProvider()

        for id in removedIDs {
            XCTAssertNil(SubscriptionServiceCatalog.service(forID: id))
            let historicalService = SubscriptionCatalogService(
                id: id,
                displayName: id,
                domain: "example.com"
            )!
            XCTAssertEqual(provider.logoSource(for: historicalService), .systemFallback("repeat.circle.fill"))
        }
    }

    func testEveryCatalogServiceHasExactlyOneLocalResolution() {
        let catalogIDs = Set(SubscriptionServiceCatalog.all.map(\.id))
        let mappedIDs = Set(SubscriptionLogoMetadata.sourcesByServiceID.keys)
            .union(SubscriptionLogoMetadata.fallbackServiceIDs)

        XCTAssertEqual(mappedIDs, catalogIDs)
        XCTAssertTrue(
            Set(SubscriptionLogoMetadata.sourcesByServiceID.keys)
                .isDisjoint(with: SubscriptionLogoMetadata.fallbackServiceIDs)
        )
        XCTAssertEqual(SubscriptionLogoMetadata.sourcesByServiceID.count, 57)
        XCTAssertEqual(SubscriptionLogoMetadata.fallbackServiceIDs.count, 0)
    }

    func testGeneratedAssetsExistForEveryMappedService() {
        let assetRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Assets.xcassets/SubscriptionLogos")

        for source in SubscriptionLogoMetadata.sourcesByServiceID.values {
            let name: String
            switch source {
            case let .appIcon(assetName), let .brandAsset(assetName), let .simpleIcon(assetName, _):
                name = assetName
            case .systemFallback:
                XCTFail("Mapped service did not resolve to an asset")
                continue
            }
            let imageSet = assetRoot.appendingPathComponent("\(name).imageset")
            let hasSVG = FileManager.default.fileExists(atPath: imageSet.appendingPathComponent("icon.svg").path)
            let hasPNG = FileManager.default.fileExists(atPath: imageSet.appendingPathComponent("icon.png").path)
            XCTAssertTrue(hasSVG || hasPNG, "Missing generated local asset for \(name)")
        }
    }

    func testCuratedOverridesHaveAuditableOfficialProvenance() throws {
        let provenanceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/subscription_logo_provenance.json")
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: provenanceURL)) as? [String: Any]
        )
        let services = try XCTUnwrap(payload["services"] as? [[String: Any]])
        let overrides = services.filter {
            ["adobe-creative-cloud", "icloud-plus", "xbox-game-pass"].contains($0["serviceID"] as? String)
        }

        XCTAssertEqual(
            Set(overrides.compactMap { $0["serviceID"] as? String }),
            Set(["adobe-creative-cloud", "icloud-plus", "xbox-game-pass"])
        )
        for override in overrides {
            let sourceURL = try XCTUnwrap(override["sourceURL"] as? String)
            XCTAssertTrue(sourceURL.hasPrefix("https://"))
            XCTAssertFalse((override["sourceName"] as? String ?? "").isEmpty)
            XCTAssertFalse((override["notes"] as? String ?? "").isEmpty)
            XCTAssertEqual(override["resolution"] as? String, "local")
            XCTAssertEqual(override["sourceType"] as? String, "OFFICIAL PRODUCT ICON")
        }
    }

    func testHistoricalTransactionResolvesCatalogWithoutLiveSubscription() throws {
        struct HistoricalTransactionLike {
            let subscriptionServiceID: String?
        }
        let transaction = HistoricalTransactionLike(subscriptionServiceID: "netflix")

        XCTAssertEqual(SubscriptionServiceCatalog.service(forID: transaction.subscriptionServiceID)?.id, "netflix")
        XCTAssertEqual(SubscriptionServiceCatalog.service(forID: transaction.subscriptionServiceID)?.domain, "netflix.com")
        let service = try XCTUnwrap(SubscriptionServiceCatalog.service(forID: transaction.subscriptionServiceID))
        XCTAssertEqual(
            LocalSubscriptionLogoProvider().logoSource(for: service),
            .appIcon(assetName: "subscription-app-icon-netflix")
        )
    }

    func testUnknownServiceIDRemainsSafeAndDoesNotRewriteValue() {
        let persistedID = "retired-service"
        XCTAssertNil(SubscriptionServiceCatalog.service(forID: persistedID))
        XCTAssertEqual(persistedID, "retired-service")
    }

    func testAutoGeneratedSubscriptionNoteSuppression() {
        let catalogBrief = RemoteSubscriptionBriefDTO(
            id: UUID(),
            serviceID: "amazon-prime",
            displayName: "Amazon Prime"
        )
        XCTAssertTrue(SubscriptionDisplayIdentity.isAutoGeneratedServiceNote("Amazon Prime", subscription: catalogBrief))
        XCTAssertTrue(SubscriptionDisplayIdentity.isAutoGeneratedServiceNote("amazon-prime", subscription: catalogBrief))
        XCTAssertFalse(SubscriptionDisplayIdentity.isAutoGeneratedServiceNote("Family shared plan", subscription: catalogBrief))

        let customBrief = RemoteSubscriptionBriefDTO(
            id: UUID(),
            serviceID: nil,
            displayName: "Custom Gym"
        )
        XCTAssertTrue(SubscriptionDisplayIdentity.isAutoGeneratedServiceNote("Custom Gym", subscription: customBrief))
        XCTAssertFalse(SubscriptionDisplayIdentity.isAutoGeneratedServiceNote("Personal training", subscription: customBrief))
    }

    func testSubscriptionDisplayIdentityServiceNameResolution() {
        let amazonBrief = RemoteSubscriptionBriefDTO(
            id: UUID(),
            serviceID: "amazon-prime",
            displayName: "Amazon Prime"
        )
        XCTAssertEqual(SubscriptionDisplayIdentity.serviceName(for: amazonBrief), "Amazon Prime")

        let chatGPTBrief = RemoteSubscriptionBriefDTO(
            id: UUID(),
            serviceID: "chatgpt",
            displayName: nil
        )
        XCTAssertEqual(SubscriptionDisplayIdentity.serviceName(for: chatGPTBrief), "ChatGPT")

        let customBrief = RemoteSubscriptionBriefDTO(
            id: UUID(),
            serviceID: nil,
            displayName: "Custom Gym"
        )
        XCTAssertEqual(SubscriptionDisplayIdentity.serviceName(for: customBrief), "Custom Gym")

        let emptyBrief = RemoteSubscriptionBriefDTO(
            id: UUID(),
            serviceID: nil,
            displayName: nil
        )
        XCTAssertEqual(SubscriptionDisplayIdentity.serviceName(for: emptyBrief), AppLocalization.string("subscription.detail"))
    }
}
