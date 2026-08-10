import Foundation

struct AppToast: Equatable, Identifiable {
    enum Kind: Equatable {
        case expenseAdded
        case incomeAdded
        case categoryAdded
        case accountAdded

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
            }
        }
    }

    let id: UUID
    let kind: Kind
    let title: String
    let amount: String

    init(id: UUID = UUID(), kind: Kind, amount: String) {
        self.id = id
        self.kind = kind
        self.title = AppLocalization.string(kind.titleKey)
        self.amount = amount
    }

    var accessibilityAnnouncement: String {
        amount.isEmpty ? title : "\(title), \(amount)"
    }
}
