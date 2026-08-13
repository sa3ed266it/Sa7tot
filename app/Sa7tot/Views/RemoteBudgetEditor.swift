import Foundation
import SwiftUI

private enum RemoteBudgetScope: String, CaseIterable, Identifiable {
    case overall
    case category

    var id: String { rawValue }
}

@available(iOS 26.0, *)
struct RemoteBudgetEditor: View {
    @EnvironmentObject private var store: FinancialRemoteStore
    @Environment(\.dismiss) private var dismiss

    let overallBudgetCreated: Bool
    let mainBudget: RemoteMainBudgetDTO?
    let categoryBudget: RemoteCategoryBudgetDTO?
    let defaultCurrencyCode: String
    @State private var scope: RemoteBudgetScope
    @State private var selectedCategoryID: UUID?
    @State private var period: BudgetTimeFrame
    @State private var amountText: String
    @State private var currencyCode: String
    @State private var isSaving = false
    @State private var mutationError: AppError?

    init(
        overallBudgetCreated: Bool = false,
        mainBudget: RemoteMainBudgetDTO? = nil,
        categoryBudget: RemoteCategoryBudgetDTO? = nil,
        defaultCurrencyCode: String = "EUR"
    ) {
        self.overallBudgetCreated = overallBudgetCreated
        self.mainBudget = mainBudget
        self.categoryBudget = categoryBudget
        self.defaultCurrencyCode = defaultCurrencyCode
        let editingCategory = categoryBudget != nil
        let startsWithCategoryBudget = editingCategory || (overallBudgetCreated && mainBudget == nil)
        _scope = State(initialValue: startsWithCategoryBudget ? .category : .overall)
        _selectedCategoryID = State(initialValue: categoryBudget?.categoryID)
        _period = State(initialValue: Self.timeFrame(for: mainBudget?.periodType ?? categoryBudget?.periodType ?? .week))
        let amountMinor = mainBudget?.amountMinor ?? categoryBudget?.amountMinor ?? 0
        _amountText = State(initialValue: Self.amountString(minor: amountMinor, exponent: mainBudget?.currencyExponent ?? categoryBudget?.currencyExponent ?? 2))
        _currencyCode = State(initialValue: mainBudget?.currencyCode ?? categoryBudget?.currencyCode ?? defaultCurrencyCode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.key("budget.type")) {
                    Picker(AppLocalization.key("budget.scope"), selection: $scope) {
                        Text(AppLocalization.key("budget.overall")).tag(RemoteBudgetScope.overall)
                        Text(AppLocalization.key("budget.category")).tag(RemoteBudgetScope.category)
                    }
                    .disabled(overallBudgetCreated || mainBudget != nil || categoryBudget != nil)
                    if scope == .category {
                        Picker(AppLocalization.key("common.category"), selection: $selectedCategoryID) {
                            Text(AppLocalization.key("category.select")).tag(UUID?.none)
                            ForEach(store.categories.filter { !$0.income }) { category in
                                Text(category.name).tag(Optional(category.id))
                            }
                        }
                    }
                }
                Section(AppLocalization.key("common.period")) {
                    Picker(AppLocalization.key("common.frequency"), selection: $period) {
                        Text(AppLocalization.key("budget.daily")).tag(BudgetTimeFrame.day)
                        Text(AppLocalization.key("budget.weekly")).tag(BudgetTimeFrame.week)
                        Text(AppLocalization.key("budget.monthly")).tag(BudgetTimeFrame.month)
                        Text(AppLocalization.key("budget.yearly")).tag(BudgetTimeFrame.year)
                    }
                }
                Section(AppLocalization.key("common.amount")) {
                    TextField("0,00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }

                if let mutationError {
                    Section {
                        InlineMutationErrorView(error: mutationError) {
                            self.mutationError = nil
                        }
                    }
                }
            }
            .navigationTitle(AppLocalization.key("budget.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.key("action.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.key("action.save")) { save() }
                        .disabled(isSaving || parsedMinor == nil || (scope == .category && selectedCategoryID == nil))
                }
            }
        }
        .presentationDetents([.fraction(0.74), .large])
        .presentationDragIndicator(.visible)
    }

    private var exponent: Int { mainBudget?.currencyExponent ?? categoryBudget?.currencyExponent ?? 2 }
    private var parsedMinor: Int64? {
        guard let value = BudgetAmountParser.decimal(from: amountText), BudgetAmountParser.isValid(value) else { return nil }
        return NSDecimalNumber(decimal: value).multiplying(by: NSDecimalNumber(value: pow(10.0, Double(exponent)))).int64Value
    }

    private func save() {
        guard let amountMinor = parsedMinor else { return }
        mutationError = nil
        isSaving = true
        let remotePeriod: RemoteBudgetPeriod = switch period { case .day: .day; case .week: .week; case .month: .month; case .year: .year }
        let payload = RemoteBudgetMutationPayload(amountMinor: amountMinor, currencyCode: currencyCode, currencyExponent: exponent, periodType: remotePeriod)
        Task {
            do {
                if scope == .overall {
                    try await store.saveMainBudget(payload)
                } else if let selectedCategoryID {
                    try await store.saveCategoryBudget(categoryID: selectedCategoryID, payload: payload)
                }
                dismiss()
            } catch {
                mutationError = AppError.from(error)
                isSaving = false
            }
        }
    }

    private static func timeFrame(for period: RemoteBudgetPeriod) -> BudgetTimeFrame {
        switch period { case .day: .day; case .week: .week; case .month: .month; case .year: .year }
    }

    private static func amountString(minor: Int64, exponent: Int) -> String {
        FinancialFormatting.digits(minorUnits: minor, currencyCode: "", exponent: exponent)
    }
}
