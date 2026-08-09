import Foundation

enum CategoryIconDescriptor: Hashable {
    case sfSymbol(String)
    case asset(String)
    case appLogo(String)

    static let fallback: CategoryIconDescriptor = .sfSymbol("tag.fill")

    init(identifier: String?) {
        guard let identifier, let separator = identifier.firstIndex(of: ":") else {
            self = .fallback
            return
        }
        let value = String(identifier[identifier.index(after: separator)...])
        guard !value.isEmpty else {
            self = .fallback
            return
        }
        switch identifier[..<separator] {
        case "sf": self = .sfSymbol(value)
        case "asset": self = .asset(value)
        case "logo": self = .appLogo(value)
        default: self = .fallback
        }
    }

    var identifier: String {
        switch self {
        case .sfSymbol(let value): "sf:\(value)"
        case .asset(let value): "asset:\(value)"
        case .appLogo(let value): "logo:\(value)"
        }
    }
}
