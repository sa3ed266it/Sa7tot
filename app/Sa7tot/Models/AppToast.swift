import Foundation

struct AppToast: Equatable, Identifiable {
    enum Kind: Equatable {
        case expenseAdded
        case incomeAdded
        case categoryAdded
        case accountAdded
        case error(titleKey: String, messageKey: String)

        var titleKey: String {
            switch self {
            case .expenseAdded:
                return "toast.movement.expenseAdded"
            case .incomeAdded:
                return "toast.movement.incomeAdded"
            case .categoryAdded:
                return "toast.category.added"
            case .accountAdded:
                return "toast.account.added"
            case let .error(titleKey, _):
                return titleKey
            }
        }
    }

    let id: UUID
    let kind: Kind
    let title: String
    let amount: String
    let message: String?

    init(id: UUID = UUID(), kind: Kind, amount: String = "") {
        self.id = id
        self.kind = kind
        self.title = AppLocalization.string(kind.titleKey)
        self.amount = amount
        if case let .error(_, messageKey) = kind {
            self.message = AppLocalization.string(messageKey)
        } else {
            self.message = nil
        }
    }

    var accessibilityAnnouncement: String {
        if let message {
            return "\(title), \(message)"
        }
        return amount.isEmpty ? title : "\(title), \(amount)"
    }
}
