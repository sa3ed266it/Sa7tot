import SwiftUI
import UIKit

protocol CategoryAppLogoProviding {
    func image(for logoID: String) -> Image?
}

struct EmptyCategoryAppLogoProvider: CategoryAppLogoProviding {
    func image(for logoID: String) -> Image? { nil }
}

enum Sa7totIconRole {
    case toolbar, inline, listRow, category, status

    var size: CGFloat {
        switch self { case .toolbar: 21; case .inline: 19; case .listRow: 16; case .category: 20; case .status: 18 }
    }

    var weight: Font.Weight {
        switch self { case .inline: .medium; default: .semibold }
    }
}

enum CategoryIconKind: Hashable { case expense, income }

struct CategoryIconOption: Identifiable, Hashable {
    let id: String
    let iconIdentifier: String
    let title: String
    let group: CategoryIconGroup
    let supportedKinds: [CategoryIconKind]
    var symbolName: String { String(iconIdentifier.dropFirst(3)) }

    init(_ symbol: String, _ title: String, _ group: CategoryIconGroup, kinds: [CategoryIconKind] = [.expense, .income]) {
        id = "sf:\(symbol)"; iconIdentifier = "sf:\(symbol)"; self.title = title; self.group = group; supportedKinds = kinds
    }
}

enum CategoryIconGroup: String, CaseIterable, Identifiable {
    case food = "Cibo", transport = "Trasporti", home = "Casa", shopping = "Acquisti", health = "Salute", people = "Persone", work = "Lavoro", leisure = "Tempo libero", finance = "Finanze", travel = "Viaggi", other = "Altro"
    var id: String { rawValue }
}

enum CategoryIconCatalog {
    static let all: [CategoryIconOption] = [
        // Food and groceries
        .init("fork.knife", "Cibo", .food), .init("takeoutbag.and.cup.and.straw.fill", "Asporto", .food), .init("cup.and.saucer.fill", "Caffè", .food), .init("wineglass.fill", "Vino", .food), .init("cart.fill", "Spesa", .food),
        .init("basket.fill", "Cestino", .food), .init("birthday.cake.fill", "Torta", .food), .init("carrot.fill", "Verdura", .food), .init("fish.fill", "Pesce", .food), .init("popcorn.fill", "Snack", .food),

        // Transport and travel
        .init("tram.fill", "Tram", .transport), .init("car.fill", "Auto", .transport), .init("bus.fill", "Autobus", .transport), .init("fuelpump.fill", "Carburante", .transport), .init("bicycle", "Bici", .transport),
        .init("train.side.front.car", "Treno", .transport), .init("scooter", "Scooter", .transport), .init("parkingsign.circle.fill", "Parcheggio", .transport), .init("steeringwheel", "Guida", .transport), .init("airplane", "Aereo", .travel),
        .init("globe.europe.africa.fill", "Estero", .travel), .init("tent.fill", "Campeggio", .travel), .init("bed.double.fill", "Hotel", .travel), .init("map.fill", "Mappa", .travel), .init("suitcase.fill", "Valigia", .travel),

        // Home and bills
        .init("house.fill", "Casa", .home), .init("building.2.fill", "Edificio", .home), .init("lightbulb.fill", "Luce", .home), .init("bolt.fill", "Energia", .home), .init("drop.fill", "Acqua", .home), .init("wifi", "Internet", .home),
        .init("iphone.gen3", "Telefono", .home), .init("tv.fill", "Televisione", .home), .init("washer.fill", "Lavatrice", .home), .init("fan.fill", "Clima", .home), .init("wrench.and.screwdriver.fill", "Manutenzione", .home),

        // Shopping and personal care
        .init("bag.fill", "Borsa", .shopping), .init("tshirt.fill", "Abbigliamento", .shopping), .init("shoe.2.fill", "Scarpe", .shopping), .init("tag.fill", "Etichetta", .shopping), .init("gift.fill", "Regalo", .shopping),
        .init("storefront.fill", "Negozio", .shopping), .init("basket", "Acquisti", .shopping), .init("eyeglasses", "Ottica", .shopping), .init("scissors", "Parrucchiere", .shopping), .init("sparkles", "Cura", .shopping),

        // Health and family
        .init("cross.case.fill", "Salute", .health), .init("heart.fill", "Benessere", .health), .init("pills.fill", "Farmacia", .health), .init("stethoscope", "Medico", .health), .init("figure.run", "Fitness", .health),
        .init("person.2.fill", "Famiglia", .people), .init("person.3.fill", "Gruppo", .people), .init("pawprint.fill", "Animali", .people), .init("dog.fill", "Cane", .people), .init("figure.2.and.child.holdinghands", "Bambini", .people),

        // Work, education and leisure
        .init("briefcase.fill", "Lavoro", .work), .init("laptopcomputer", "Computer", .work), .init("building.columns.fill", "Ufficio", .work), .init("graduationcap.fill", "Studio", .work), .init("book.fill", "Libri", .work),
        .init("gamecontroller.fill", "Giochi", .leisure), .init("music.note", "Musica", .leisure), .init("film.fill", "Cinema", .leisure), .init("ticket.fill", "Eventi", .leisure), .init("paintpalette.fill", "Creatività", .leisure), .init("sportscourt.fill", "Sport", .leisure),

        // Money, banking and subscriptions
        .init("banknote.fill", "Denaro", .finance), .init("arrow.down.circle.fill", "Entrata", .finance), .init("building.columns.fill", "Banca", .finance), .init("creditcard.fill", "Carta", .finance), .init("wallet.pass.fill", "Portafoglio", .finance), .init("chart.line.uptrend.xyaxis", "Risparmi", .finance), .init("hand.thumbsup.fill", "Mancia", .finance),
        .init("arrow.left.arrow.right", "Trasferimento", .finance), .init("arrow.triangle.2.circlepath", "Ricorrenza", .finance), .init("calendar.badge.clock", "Abbonamento", .finance), .init("percent", "Sconto", .finance), .init("dollarsign.circle.fill", "Valuta", .finance),

        // Other useful category concepts
        .init("calendar", "Calendario", .other), .init("clock.fill", "Tempo", .other), .init("bell.fill", "Avviso", .other), .init("lock.fill", "Sicurezza", .other), .init("ellipsis.circle.fill", "Altro", .other)
    ]
    static func options(for kind: CategoryIconKind) -> [CategoryIconOption] { all.filter { $0.supportedKinds.contains(kind) && UIImage(systemName: $0.symbolName) != nil } }
}

enum CategoryIconPresentation {
    enum Style: Equatable { case plain, selection }

    static func descriptor(for identifier: String?) -> CategoryIconDescriptor {
        let parsed = CategoryIconDescriptor(identifier: identifier)
        if case .sfSymbol(let symbol) = parsed, UIImage(systemName: symbol) == nil { return .fallback }
        return parsed
    }
    static func foreground(for storedColour: String) -> Color { .primary }
}

enum Sa7totSymbolResolver {
    static func resolved(_ symbol: String, fallback: String = "tag.fill") -> String {
        UIImage(systemName: symbol) == nil ? fallback : symbol
    }

    static func image(_ symbol: String, fallback: String = "tag.fill") -> UIImage? {
        UIImage(systemName: resolved(symbol, fallback: fallback))
    }
}

struct CategoryIconView: View {
    let descriptor: CategoryIconDescriptor
    var role: Sa7totIconRole = .category
    var style: CategoryIconPresentation.Style = .plain
    var tint: Color = .primary
    var accessibilityLabel: String = ""
    var logoProvider: CategoryAppLogoProviding = EmptyCategoryAppLogoProvider()

    var body: some View {
        content
            .frame(minWidth: role.size, minHeight: role.size)
            .overlay { if style == .selection { RoundedRectangle(cornerRadius: 8).stroke(tint, lineWidth: 2) } }
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder private var content: some View {
        switch descriptor {
        case .sfSymbol(let symbol):
            Image(systemName: UIImage(systemName: symbol) == nil ? "tag.fill" : symbol)
                .font(.system(size: role.size, weight: role.weight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        case .asset(let name), .appLogo(let name):
            if let image = logoProvider.image(for: name) { image.resizable().scaledToFit() }
            else { Image(systemName: "tag.fill").font(.system(size: role.size, weight: role.weight)).foregroundStyle(tint) }
        }
    }
}

struct Sa7totIconTile: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 32

    var body: some View {
        CategoryIconView(descriptor: .sfSymbol(systemName), role: .listRow, tint: .primary)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct Sa7totIcon: View {
    let systemName: String
    let role: Sa7totIconRole
    var tint: Color = .primary
    var body: some View { CategoryIconView(descriptor: .sfSymbol(systemName), role: role, tint: tint).accessibilityHidden(true) }
}
