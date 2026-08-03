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

enum CategoryIconKind: Hashable {
    case expense
    case income
}

enum CategoryIconGroup: String, CaseIterable, Identifiable {
    case food = "Cibo"
    case transport = "Trasporti"
    case home = "Casa"
    case shopping = "Acquisti"
    case health = "Salute"
    case people = "Persone"
    case work = "Lavoro"
    case leisure = "Tempo libero"
    case finance = "Finanze"
    case travel = "Viaggi"
    case other = "Altro"

    var id: String { rawValue }
}

struct CategoryIconOption: Identifiable, Hashable {
    let id: String
    let symbolName: String
    let title: String
    let group: CategoryIconGroup
    let supportedKinds: [CategoryIconKind]

    init(_ symbolName: String, _ title: String, _ group: CategoryIconGroup, kinds: [CategoryIconKind] = [.expense, .income]) {
        self.id = symbolName
        self.symbolName = symbolName
        self.title = title
        self.group = group
        self.supportedKinds = kinds
    }
}

enum CategoryIconCatalog {
    static let all: [CategoryIconOption] = [
        CategoryIconOption("fork.knife", "Cibo", .food),
        CategoryIconOption("takeoutbag.and.cup.and.straw.fill", "Asporto", .food),
        CategoryIconOption("cup.and.saucer.fill", "Caffè", .food),
        CategoryIconOption("wineglass.fill", "Vino", .food),
        CategoryIconOption("birthday.cake.fill", "Compleanno", .food),
        CategoryIconOption("cart.fill", "Spesa", .food),
        CategoryIconOption("car.fill", "Auto", .transport),
        CategoryIconOption("bus.fill", "Autobus", .transport),
        CategoryIconOption("tram.fill", "Tram", .transport),
        CategoryIconOption("train.side.front.car", "Treno", .transport),
        CategoryIconOption("bicycle", "Bicicletta", .transport),
        CategoryIconOption("airplane", "Aereo", .transport),
        CategoryIconOption("fuelpump.fill", "Carburante", .transport),
        CategoryIconOption("house.fill", "Casa", .home),
        CategoryIconOption("building.2.fill", "Edificio", .home),
        CategoryIconOption("bed.double.fill", "Camera", .home),
        CategoryIconOption("lightbulb.fill", "Luce", .home),
        CategoryIconOption("bolt.fill", "Energia", .home),
        CategoryIconOption("drop.fill", "Acqua", .home),
        CategoryIconOption("wifi", "Internet", .home),
        CategoryIconOption("bag.fill", "Borsa", .shopping),
        CategoryIconOption("tshirt.fill", "Abbigliamento", .shopping),
        CategoryIconOption("shoe.2.fill", "Scarpe", .shopping),
        CategoryIconOption("tag.fill", "Etichetta", .shopping),
        CategoryIconOption("gift.fill", "Regalo", .shopping),
        CategoryIconOption("creditcard.fill", "Carta", .shopping),
        CategoryIconOption("cross.case.fill", "Salute", .health),
        CategoryIconOption("heart.fill", "Benessere", .health),
        CategoryIconOption("pills.fill", "Farmacia", .health),
        CategoryIconOption("stethoscope", "Medico", .health),
        CategoryIconOption("dumbbell.fill", "Palestra", .health),
        CategoryIconOption("leaf.fill", "Natura", .health),
        CategoryIconOption("person.fill", "Persona", .people),
        CategoryIconOption("person.2.fill", "Famiglia", .people),
        CategoryIconOption("pawprint.fill", "Animali", .people),
        CategoryIconOption("graduationcap.fill", "Istruzione", .people),
        CategoryIconOption("briefcase.fill", "Lavoro", .work),
        CategoryIconOption("laptopcomputer", "Computer", .work),
        CategoryIconOption("book.fill", "Libro", .work),
        CategoryIconOption("doc.text.fill", "Documento", .work),
        CategoryIconOption("gamecontroller.fill", "Giochi", .leisure),
        CategoryIconOption("film.fill", "Cinema", .leisure),
        CategoryIconOption("music.note", "Musica", .leisure),
        CategoryIconOption("tv.fill", "Televisione", .leisure),
        CategoryIconOption("camera.fill", "Foto", .leisure),
        CategoryIconOption("banknote.fill", "Denaro", .finance),
        CategoryIconOption("building.columns.fill", "Banca", .finance),
        CategoryIconOption("wallet.pass.fill", "Portafoglio", .finance),
        CategoryIconOption("chart.bar.fill", "Investimenti", .finance),
        CategoryIconOption("eurosign.circle.fill", "Euro", .finance),
        CategoryIconOption("arrow.left.arrow.right", "Trasferimento", .finance),
        CategoryIconOption("suitcase.fill", "Valigia", .travel),
        CategoryIconOption("map.fill", "Mappa", .travel),
        CategoryIconOption("globe.europe.africa.fill", "Mondo", .travel),
        CategoryIconOption("tent.fill", "Campeggio", .travel),
        CategoryIconOption("arrow.triangle.2.circlepath", "Ricorrenza", .other),
        CategoryIconOption("calendar", "Calendario", .other),
        CategoryIconOption("bell.fill", "Avviso", .other),
        CategoryIconOption("phone.fill", "Telefono", .other),
        CategoryIconOption("envelope.fill", "Messaggio", .other),
        CategoryIconOption("ellipsis.circle.fill", "Altro", .other),
        CategoryIconOption("star.fill", "Preferito", .other)
    ]

    static func options(for kind: CategoryIconKind) -> [CategoryIconOption] {
        all.filter { $0.supportedKinds.contains(kind) && UIImage(systemName: $0.symbolName) != nil }
    }
}

enum CategoryIconStorage {
    static let prefix = "sf:"

    static func encode(symbolName: String) -> String {
        prefix + symbolName
    }

    static func storedSymbol(from value: String) -> String? {
        guard value.hasPrefix(prefix) else { return nil }
        let symbol = String(value.dropFirst(prefix.count))
        return UIImage(systemName: symbol) == nil ? nil : symbol
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
    static func symbol(for name: String, storedValue: String? = nil) -> String {
        if let storedValue, let storedSymbol = CategoryIconStorage.storedSymbol(from: storedValue) {
            return storedSymbol
        }

        return Sa7totSymbolResolver.resolved(CategoryIconRegistry.symbol(for: name))
    }

    static func foreground(for storedColour: String) -> Color {
        .primary
    }

    static func background(for storedColour: String) -> Color {
        Color(hex: storedColour).opacity(0.22)
    }
}

enum CategoryIconMigration {
    static func migrate(categories: [Category]) -> Bool {
        var changed = false
        for category in categories {
            let canonical = CategoryIconPresentation.symbol(for: category.wrappedName, storedValue: category.emoji)
            let encoded = CategoryIconStorage.encode(symbolName: canonical)
            if category.emoji != encoded {
                category.emoji = encoded
                changed = true
            }
        }
        return changed
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
    var storedValue: String?
    var size: CGFloat = 44
    var future = false

    var body: some View {
        Sa7totIcon(systemName: CategoryIconPresentation.symbol(for: name, storedValue: storedValue), role: .category, tint: CategoryIconPresentation.foreground(for: colour))
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
