import CoreText
import SwiftUI
import UIKit

enum ClashDisplayFont {
    static let name = "ClashDisplay-Bold"
    private static let registrationLock = NSLock()
    private static var didAttemptRegistration = false

    private static func register() -> Bool {
        registrationLock.lock()
        defer { registrationLock.unlock() }

        if didAttemptRegistration {
            return UIFont(name: name, size: 12) != nil
        }
        didAttemptRegistration = true

        guard let url = Bundle.main.url(forResource: "ClashDisplay-Bold", withExtension: "otf") else {
            assertionFailure("Clash Display Bold font asset is missing from the app bundle")
            return false
        }

        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return UIFont(name: name, size: 12) != nil
    }

    static func font(size: CGFloat) -> Font {
        guard register() else { return .system(size: size, weight: .bold) }
        return .custom(name, size: size)
    }

    static func compactFont() -> Font {
        guard register() else { return .system(.title3, design: .rounded).weight(.bold) }
        return .custom(name, size: 20, relativeTo: .title3)
    }
}

struct CategoryLogIconView: View {
    let iconIdentifier: String
    let categoryName: String?
    let colour: String
    let future: Bool
    let huge: Bool

    var body: some View {
        CategoryIconView(
            descriptor: CategoryIconPresentation.descriptor(for: iconIdentifier),
            role: huge ? .category : .listRow,
            accessibilityLabel: categoryName ?? "Altro"
        )
        .opacity(future ? 0.6 : 1)
    }

    init(iconIdentifier: String, categoryName: String? = nil, colour: String, future: Bool, huge: Bool = false) {
        self.iconIdentifier = iconIdentifier
        self.categoryName = categoryName
        self.colour = colour
        self.future = future
        self.huge = huge
    }
}

struct DottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width / 2, y: 0))
        path.addLine(to: CGPoint(x: rect.width / 2, y: rect.height))
        return path
    }
}

struct EmptyStatePreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct NoResultsView: View {
    let fullscreen: Bool

    var body: some View {
        Group {
            if fullscreen {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray.full.fill")
                        .font(.system(.largeTitle, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(Color.SubtitleText)
                    Text("Nessun movimento trovato.")
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(Color.SubtitleText)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: UIScreen.main.bounds.height * 0.7)
                .opacity(0.7)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 38, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                    Text("Nessun movimento trovato.")
                        .font(.system(size: 21, weight: .medium, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .opacity(0.7)
                .padding(.top, 50)
            }
        }
        .preference(key: EmptyStatePreferenceKey.self, value: true)
    }
}
