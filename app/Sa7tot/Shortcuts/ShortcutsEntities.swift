//
//  ShortcutsEntities.swift
//  sa7tot
//
//  Created by Rafael Soh on 1/8/23.
//

import AppIntents
import CoreData
import Foundation

@available(iOS 16, *)
struct IncomeCategoryEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Categoria")
    typealias DefaultQueryType = IncomeCategoryQuery
    static var defaultQuery: IncomeCategoryQuery = .init()

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Icon")
    var iconIdentifier: String

    @Property(title: "Entrata")
    var income: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)" as LocalizedStringResource, image: .init(systemName: Sa7totSharedIconPresentation.symbol(for: name, storedValue: iconIdentifier)))
    }

    init(id: UUID, name: String, iconIdentifier: String, income: Bool) {
        self.id = id
        self.name = name
        self.iconIdentifier = iconIdentifier
        self.income = income
    }
}

@available(iOS 16, *)
struct IncomeCategoryQuery: EntityStringQuery {
    func entities(matching query: String) async throws -> [IncomeCategoryEntity] {
        let dataController = DataController.shared

        let categories = dataController.getAllCategories(income: true).filter {
            $0.wrappedName.localizedCaseInsensitiveContains(query) || $0.wrappedIconIdentifier.localizedCaseInsensitiveContains(query)
        }

        return categories.compactMap { category in
            if let id = category.id {
                return IncomeCategoryEntity(id: id, name: category.wrappedName, iconIdentifier: category.wrappedIconIdentifier, income: category.income)
            } else {
                return nil
            }
        }
    }

    func entities(for identifiers: [IncomeCategoryEntity.ID]) async throws -> [IncomeCategoryEntity] {
        return identifiers.compactMap { identifier in
            let dataController = DataController.shared

            if let match = try? dataController.findCategory(withId: identifier) {
                if let id = match.id {
                    return IncomeCategoryEntity(id: id, name: match.wrappedName, iconIdentifier: match.wrappedIconIdentifier, income: match.income)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }
    }

    func suggestedEntities() async throws -> [IncomeCategoryEntity] {
        let dataController = DataController.shared

        return dataController.getAllCategories(income: true).compactMap { category in
            if let id = category.id {
                return IncomeCategoryEntity(id: id, name: category.wrappedName, iconIdentifier: category.wrappedIconIdentifier, income: category.income)
            } else {
                return nil
            }
        }
    }
}

@available(iOS 16, *)
struct ExpenseCategoryEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Categoria")
    typealias DefaultQueryType = ExpenseCategoryQuery
    static var defaultQuery: ExpenseCategoryQuery = .init()

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Icon")
    var iconIdentifier: String

    @Property(title: "Entrata")
    var income: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)" as LocalizedStringResource, image: .init(systemName: Sa7totSharedIconPresentation.symbol(for: name, storedValue: iconIdentifier)))
    }

    init(id: UUID, name: String, iconIdentifier: String, income: Bool) {
        self.id = id
        self.name = name
        self.iconIdentifier = iconIdentifier
        self.income = income
    }
}

@available(iOS 16, *)
struct ExpenseCategoryQuery: EntityStringQuery {
    func entities(matching query: String) async throws -> [ExpenseCategoryEntity] {
        let dataController = DataController.shared

        let categories = dataController.getAllCategories(income: false).filter {
            $0.wrappedName.localizedCaseInsensitiveContains(query) || $0.wrappedIconIdentifier.localizedCaseInsensitiveContains(query)
        }

        return categories.compactMap { category in
            if let id = category.id {
                return ExpenseCategoryEntity(id: id, name: category.wrappedName, iconIdentifier: category.wrappedIconIdentifier, income: category.income)
            } else {
                return nil
            }
        }
    }

    func entities(for identifiers: [ExpenseCategoryEntity.ID]) async throws -> [ExpenseCategoryEntity] {
        return identifiers.compactMap { identifier in
            let dataController = DataController.shared
            if let match = try? dataController.findCategory(withId: identifier) {
                if let id = match.id {
                    return ExpenseCategoryEntity(id: id, name: match.wrappedName, iconIdentifier: match.wrappedIconIdentifier, income: match.income)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }
    }

    func suggestedEntities() async throws -> [ExpenseCategoryEntity] {
        let dataController = DataController.shared

        return dataController.getAllCategories(income: false).compactMap { category in
            if let id = category.id {
                return ExpenseCategoryEntity(id: id, name: category.wrappedName, iconIdentifier: category.wrappedIconIdentifier, income: category.income)
            } else {
                return nil
            }
        }
    }
}

@available(iOS 16, *)
struct BudgetEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Budget")
    typealias DefaultQueryType = BudgetQuery
    static var defaultQuery: BudgetQuery = .init()

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Icon")
    var iconIdentifier: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)" as LocalizedStringResource, image: .init(systemName: Sa7totSharedIconPresentation.symbol(for: name, storedValue: iconIdentifier)))
    }

    init(id: UUID, name: String, iconIdentifier: String) {
        self.id = id
        self.name = name
        self.iconIdentifier = iconIdentifier
    }
}

@available(iOS 16, *)
struct BudgetQuery: EntityStringQuery {
    func entities(matching query: String) async throws -> [BudgetEntity] {
        let dataController = DataController.shared

        let budgets = dataController.getAllBudgets().filter {
            $0.wrappedName.localizedCaseInsensitiveContains(query) || $0.iconIdentifier.localizedCaseInsensitiveContains(query)
        }

        return budgets.compactMap { budget in
            if let id = budget.id {
                return BudgetEntity(id: id, name: budget.wrappedName, iconIdentifier: budget.iconIdentifier)
            } else {
                return nil
            }
        }
    }

    func entities(for identifiers: [BudgetEntity.ID]) async throws -> [BudgetEntity] {
        return identifiers.compactMap { identifier in
            let dataController = DataController.shared

            if let match = try? dataController.findBudget(withId: identifier) {
                if let id = match.id {
                    return BudgetEntity(id: id, name: match.wrappedName, iconIdentifier: match.iconIdentifier)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }
    }

    func suggestedEntities() async throws -> [BudgetEntity] {
        let dataController = DataController.shared

        return dataController.getAllBudgets().compactMap { budget in
            if let id = budget.id {
                return BudgetEntity(id: id, name: budget.wrappedName, iconIdentifier: budget.iconIdentifier)
            } else {
                return nil
            }
        }
    }
    }
