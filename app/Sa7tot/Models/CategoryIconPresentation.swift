import SwiftUI
import UIKit

enum Sa7totIconRole {
    case toolbar
    case inline
    case listRow
    case category
    case status

    var size: CGFloat {
        switch self {
        case .toolbar: return 21
        case .inline: return 19
        case .listRow: return 16
        case .category: return 20
        case .status: return 18
        }
    }

    var weight: Font.Weight {
        switch self {
        case .toolbar, .listRow, .category, .status: return .semibold
        case .inline: return .medium
        }
    }
}

enum Sa7totSymbolResolver {
    static func resolved(_ symbol: String, fallback: String = "tag.fill") -> String {
        UIImage(systemName: symbol) == nil ? fallback : symbol
    }

    static func image(_ symbol: String, fallback: String = "tag.fill") -> UIImage? {
        UIImage(systemName: resolved(symbol, fallback: fallback))
    }
}

struct CategoryIconPresentation {
    private static func rawSymbol(for name: String) -> String {
        let normalized = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "spesa", "spese": return "cart.fill"
        case "abbonamento", "abbonamenti": return "repeat.circle.fill"
        case "trasporti": return "tram.fill"
        case "cibo": return "fork.knife"
        case "stipendio": return "banknote.fill"
        case "casa", "affitto": return "house.fill"
        case "utenza", "utenze", "bolletta", "bollette": return "bolt.fill"
        case "famiglia": return "person.2.fill"
        case "salute": return "cross.case.fill"
        case "intrattenimento", "svago": return "gamecontroller.fill"
        case "viaggio", "viaggi": return "airplane"
        case "moda", "shopping": return "bag.fill"
        case "regali": return "gift.fill"
        case "istruzione": return "book.fill"
        case "sport": return "figure.run"
        case "animali": return "pawprint.fill"
        case "entrata", "entrate", "reddito": return "banknote.fill"
        case "rimborso": return "arrow.uturn.backward.circle.fill"
        case "risparmi": return "building.columns.fill"
        case "altro": return "tag.fill"
        default: return "tag.fill"
        }
    }

    static func symbol(for name: String) -> String {
        Sa7totSymbolResolver.resolved(rawSymbol(for: name))
    }

    static func foreground(for storedColour: String) -> Color {
        .primary
    }

    static func background(for storedColour: String) -> Color {
        Color(hex: storedColour).opacity(0.22)
    }
}

struct Sa7totIcon: View {
    let systemName: String
    let role: Sa7totIconRole
    var tint: Color = .primary

    var body: some View {
        Image(systemName: Sa7totSymbolResolver.resolved(systemName))
            .font(.system(size: role.size, weight: role.weight))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .accessibilityHidden(true)
    }
}

struct Sa7totIconTile: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 32

    var body: some View {
        Sa7totIcon(systemName: systemName, role: .listRow, tint: .white)
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct Sa7totCategoryIcon: View {
    let name: String
    let colour: String
    var size: CGFloat = 44
    var future = false

    var body: some View {
        Sa7totIcon(systemName: CategoryIconPresentation.symbol(for: name), role: .category, tint: CategoryIconPresentation.foreground(for: colour))
            .frame(width: size, height: size)
            .background {
                if future {
                    RoundedRectangle(cornerRadius: size * 0.21, style: .continuous)
                        .stroke(Color(hex: colour).opacity(0.73), lineWidth: 2)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.21, style: .continuous)
                        .fill(Color(hex: colour).opacity(0.73))
                }
            }
            .opacity(future ? 0.6 : 1)
            .accessibilityHidden(true)
    }
}
