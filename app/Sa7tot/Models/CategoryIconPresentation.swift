import SwiftUI

struct CategoryIconPresentation {
    static func symbol(for name: String) -> String {
        let normalized = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "spesa", "spese": return "cart.fill"
        case "abbonamenti": return "arrow.triangle.2.circlepath.circle.fill"
        case "trasporti": return "tram.fill"
        case "cibo": return "fork.knife"
        case "stipendio": return "banknote.fill"
        case "casa": return "house.fill"
        case "bollette": return "lightbulb.fill"
        case "salute": return "cross.case.fill"
        case "intrattenimento", "svago": return "play.tv.fill"
        case "viaggi": return "suitcase.rolling.fill"
        case "altro": return "square.grid.2x2.fill"
        case "shopping": return "bag.fill"
        case "regali": return "gift.fill"
        case "istruzione": return "book.fill"
        case "sport": return "figure.run"
        case "animali": return "pawprint.fill"
        case "entrate", "reddito": return "arrow.down.circle.fill"
        case "rimborso": return "arrow.uturn.backward.circle.fill"
        case "risparmi": return "building.columns.fill"
        default: return "tag.fill"
        }
    }

    static func foreground(for storedColour: String) -> Color {
        .primary
    }

    static func background(for storedColour: String) -> Color {
        Color(hex: storedColour).opacity(0.22)
    }
}
