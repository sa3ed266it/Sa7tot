import Foundation

enum SubscriptionServiceCategory: String, CaseIterable, Hashable, Sendable {
    case streamingVideo
    case musicAudio
    case cloudStorage
    case productivity
    case ai
    case gaming
    case fitnessWellness
    case newsReading
    case securityVPN
    case developer
    case deliveryMembership
    case other
}

struct SubscriptionCatalogService: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let domain: String
    let aliases: [String]
    let categoryHint: SubscriptionServiceCategory?

    init?(
        id: String,
        displayName: String,
        domain: String,
        aliases: [String] = [],
        categoryHint: SubscriptionServiceCategory? = nil
    ) {
        guard
            let normalizedID = SubscriptionCatalogNormalizer.serviceID(id),
            !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let normalizedDomain = SubscriptionCatalogNormalizer.domain(domain)
        else { return nil }

        self.id = normalizedID
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.domain = normalizedDomain
        self.aliases = aliases
        self.categoryHint = categoryHint
    }
}

enum SubscriptionCatalogNormalizer {
    static func serviceID(_ value: String) -> String? {
        let folded = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        let slug = folded.unicodeScalars.map { scalar -> String in
            let value = String(scalar)
            return value.rangeOfCharacter(from: .alphanumerics) != nil ? value.lowercased() : "-"
        }
        .joined()
        .split(separator: "-")
        .joined(separator: "-")

        return slug.isEmpty ? nil : slug
    }

    static func domain(_ value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        let urlString = candidate.contains("://") ? candidate : "https://\(candidate)"
        guard let host = URL(string: urlString)?.host?.lowercased() else { return nil }

        let normalized = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard !normalized.isEmpty, !normalized.contains(where: { $0.isWhitespace }) else { return nil }
        return normalized
    }

    static func searchText(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return folded.unicodeScalars.map { scalar -> String in
            let value = String(scalar)
            return value.rangeOfCharacter(from: .alphanumerics) != nil ? value.lowercased() : " "
        }
        .joined()
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
    }

    static func compactSearchText(_ value: String) -> String {
        searchText(value).replacingOccurrences(of: " ", with: "")
    }
}

enum SubscriptionServiceCatalog {
    static let all: [SubscriptionCatalogService] = [
        // Video and entertainment
        service("netflix", "Netflix", "netflix.com", aliases: ["net"], category: .streamingVideo),
        service("disney-plus", "Disney+", "disneyplus.com", aliases: ["disney plus"], category: .streamingVideo),
        service("prime-video", "Prime Video", "primevideo.com", aliases: ["amazon video"], category: .streamingVideo),
        service("amazon-prime", "Amazon Prime", "amazon.com", aliases: ["prime"], category: .deliveryMembership),
        service("apple-tv-plus", "Apple TV+", "tv.apple.com", aliases: ["apple tv"], category: .streamingVideo),
        service("youtube-premium", "YouTube Premium", "youtube.com", aliases: ["yt premium", "youtube"], category: .streamingVideo),
        service("paramount-plus", "Paramount+", "paramountplus.com", aliases: ["paramount plus"], category: .streamingVideo),
        service("discovery-plus", "discovery+", "discoveryplus.com", aliases: ["discovery plus"], category: .streamingVideo),
        service("crunchyroll", "Crunchyroll", "crunchyroll.com", category: .streamingVideo),
        service("dazn", "DAZN", "dazn.com", category: .streamingVideo),
        service("now", "NOW", "nowtv.it", aliases: ["now tv", "nowtv"], category: .streamingVideo),
        service("sky", "Sky", "sky.it", category: .streamingVideo),
        service("mediaset-infinity", "Mediaset Infinity", "mediasetinfinity.mediaset.it", aliases: ["infinity"], category: .streamingVideo),
        service("twitch", "Twitch", "twitch.tv", category: .streamingVideo),
        service("mubi", "MUBI", "mubi.com", category: .streamingVideo),

        // Music, audio, and books
        service("spotify", "Spotify", "spotify.com", category: .musicAudio),
        service("apple-music", "Apple Music", "music.apple.com", aliases: ["apple music"], category: .musicAudio),
        service("youtube-music", "YouTube Music", "music.youtube.com", aliases: ["yt music"], category: .musicAudio),
        service("audible", "Audible", "audible.com", category: .musicAudio),
        service("amazon-music", "Amazon Music", "music.amazon.com", category: .musicAudio),
        service("tidal", "TIDAL", "tidal.com", category: .musicAudio),
        service("deezer", "Deezer", "deezer.com", category: .musicAudio),
        service("storytel", "Storytel", "storytel.com", category: .newsReading),
        service("kindle-unlimited", "Kindle Unlimited", "amazon.com", aliases: ["kindle"], category: .newsReading),

        // Cloud and storage
        service("icloud-plus", "iCloud+", "icloud.com", aliases: ["icloud", "apple cloud"], category: .cloudStorage),
        service("google-one", "Google One", "one.google.com", aliases: ["google storage"], category: .cloudStorage),
        service("dropbox", "Dropbox", "dropbox.com", category: .cloudStorage),
        service("microsoft-onedrive", "Microsoft OneDrive", "onedrive.com", aliases: ["onedrive"], category: .cloudStorage),
        service("microsoft-365", "Microsoft 365", "microsoft.com", aliases: ["office", "office 365"], category: .productivity),
        service("pcloud", "pCloud", "pcloud.com", category: .cloudStorage),

        // Productivity and creative tools
        service("adobe-creative-cloud", "Adobe Creative Cloud", "adobe.com", aliases: ["adobe", "creative cloud"], category: .productivity),
        service("canva", "Canva", "canva.com", category: .productivity),
        service("notion", "Notion", "notion.so", category: .productivity),
        service("evernote", "Evernote", "evernote.com", category: .productivity),
        service("todoist", "Todoist", "todoist.com", category: .productivity),
        service("grammarly", "Grammarly", "grammarly.com", category: .productivity),
        service("figma", "Figma", "figma.com", category: .productivity),
        service("zoom", "Zoom", "zoom.us", category: .productivity),
        service("slack", "Slack", "slack.com", category: .productivity),

        // AI
        service("chatgpt", "ChatGPT", "chatgpt.com", aliases: ["chat gpt", "open ai", "openai"], category: .ai),
        service("claude", "Claude", "claude.ai", aliases: ["anthropic"], category: .ai),
        service("perplexity", "Perplexity", "perplexity.ai", category: .ai),

        // Gaming
        service("playstation-plus", "PlayStation Plus", "playstation.com", aliases: ["ps plus", "playstation"], category: .gaming),
        service("xbox-game-pass", "Xbox Game Pass", "xbox.com", aliases: ["game pass", "xbox"], category: .gaming),
        service("nintendo-switch-online", "Nintendo Switch Online", "nintendo.com", aliases: ["nintendo online", "switch online"], category: .gaming),

        // Security and developer tools
        service("1password", "1Password", "1password.com", aliases: ["one password"], category: .securityVPN),
        service("nordvpn", "NordVPN", "nordvpn.com", category: .securityVPN),
        service("expressvpn", "ExpressVPN", "expressvpn.com", category: .securityVPN),
        service("surfshark", "Surfshark", "surfshark.com", category: .securityVPN),
        service("proton-vpn", "Proton VPN", "protonvpn.com", aliases: ["proton vpn"], category: .securityVPN),
        service("github-copilot", "GitHub Copilot", "github.com", aliases: ["copilot"], category: .developer),

        // Fitness, wellness, and memberships
        service("myfitnesspal", "MyFitnessPal", "myfitnesspal.com", category: .fitnessWellness),
        service("headspace", "Headspace", "headspace.com", category: .fitnessWellness),
        service("calm", "Calm", "calm.com", category: .fitnessWellness),
        service("uber-one", "Uber One", "uber.com", aliases: ["uber one"], category: .deliveryMembership),
        service("deliveroo", "Deliveroo", "deliveroo.com", category: .deliveryMembership),
        service("glovo", "Glovo", "glovoapp.com", category: .deliveryMembership)
    ]

    private static let servicesByID: [String: SubscriptionCatalogService] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func service(forID serviceID: String?) -> SubscriptionCatalogService? {
        guard let normalizedID = serviceID.flatMap(SubscriptionCatalogNormalizer.serviceID) else { return nil }
        return servicesByID[normalizedID]
    }

    static func search(_ query: String) -> [SubscriptionCatalogService] {
        let normalizedQuery = SubscriptionCatalogNormalizer.searchText(query)
        guard !normalizedQuery.isEmpty else { return all }
        let compactQuery = SubscriptionCatalogNormalizer.compactSearchText(query)

        let ranked: [(rank: Int, index: Int, service: SubscriptionCatalogService)] = all.enumerated()
            .compactMap { element -> (rank: Int, index: Int, service: SubscriptionCatalogService)? in
                let index = element.offset
                let service = element.element
                let candidates = [service.id, service.displayName, service.domain] + service.aliases
                let ranks = candidates.compactMap { candidate -> Int? in
                    let normalizedCandidate = SubscriptionCatalogNormalizer.searchText(candidate)
                    let compactCandidate = SubscriptionCatalogNormalizer.compactSearchText(candidate)

                    if normalizedCandidate == normalizedQuery || compactCandidate == compactQuery { return 0 }
                    if normalizedCandidate.hasPrefix(normalizedQuery) || compactCandidate.hasPrefix(compactQuery) { return 1 }
                    if normalizedCandidate.contains(normalizedQuery) || compactCandidate.contains(compactQuery) { return 2 }
                    return nil
                }

                guard let rank = ranks.min() else { return nil }
                return (rank, index, service)
            }
        return ranked
            .sorted {
                if $0.0 != $1.0 { return $0.0 < $1.0 }
                return $0.1 < $1.1
            }
            .map(\.2)
    }

    private static func service(
        _ id: String,
        _ displayName: String,
        _ domain: String,
        aliases: [String] = [],
        category: SubscriptionServiceCategory
    ) -> SubscriptionCatalogService {
        guard let service = SubscriptionCatalogService(
            id: id,
            displayName: displayName,
            domain: domain,
            aliases: aliases,
            categoryHint: category
        ) else {
            preconditionFailure("Invalid subscription catalog entry: \(id)")
        }
        return service
    }
}
