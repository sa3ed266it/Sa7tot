import Foundation

struct AppToast: Equatable, Identifiable {
    enum Kind: Equatable {
        case expenseAdded
        case incomeAdded

        var titleKey: String {
            switch self {
            case .expenseAdded:
                return "toast.movement.expenseAdded"
            case .incomeAdded:
                return "toast.movement.incomeAdded"
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
}
