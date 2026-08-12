import SwiftUI
import UIKit
import Lottie

enum Sa7totLoaderSize: CGFloat {
    case regular = 48
    case compact = 22
}

enum Sa7totLoaderColor {
    case automatic
    case light
    case dark
    case custom(Color)
}

struct Sa7totLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let size: Sa7totLoaderSize
    let color: Sa7totLoaderColor
    var accessibilityLabel: String = AppLocalization.string("loader.loading")

    init(
        size: Sa7totLoaderSize = .regular,
        color: Sa7totLoaderColor = .automatic,
        accessibilityLabel: String = AppLocalization.string("loader.loading")
    ) {
        self.size = size
        self.color = color
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        Group {
            if reduceMotion {
                animationView
                    .paused(at: .progress(0))
                    .resizable()
            } else {
                animationView
                    .looping()
                    .resizable()
            }
        }
        .frame(width: size.rawValue, height: size.rawValue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }

    private var animationView: LottieView<EmptyView> {
        LottieView(animation: LottieAnimation.named("LoadingSpinner", bundle: .main))
            .configure { animation in
                animation.backgroundColor = .clear
                animation.setValueProvider(
                    ColorValueProvider(resolvedLottieColor),
                    keypath: AnimationKeypath(keypath: "**.Color")
                )
            }
    }

    private var resolvedLottieColor: LottieColor {
        let swiftUIColor: Color
        switch color {
        case .automatic:
            swiftUIColor = colorScheme == .dark ? .white : .black
        case .light:
            swiftUIColor = .white
        case .dark:
            swiftUIColor = .black
        case let .custom(value):
            swiftUIColor = value
        }

        let uiColor = UIColor(swiftUIColor)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return LottieColor(r: 1, g: 1, b: 1, a: 1)
        }
        return LottieColor(r: Double(red), g: Double(green), b: Double(blue), a: Double(alpha))
    }
}
