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
    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) private var currencyCode = Locale.current.currencyCode ?? "EUR"

    let overallBudgetCreated: Bool
    let mainBudget: RemoteMainBudgetDTO?
    let categoryBudget: RemoteCategoryBudgetDTO?
    @State private var scope: RemoteBudgetScope
    @State private var selectedCategoryID: UUID?
    @State private var period: BudgetTimeFrame
    @State private var amountText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(overallBudgetCreated: Bool = false, mainBudget: RemoteMainBudgetDTO? = nil, categoryBudget: RemoteCategoryBudgetDTO? = nil) {
        self.overallBudgetCreated = overallBudgetCreated
        self.mainBudget = mainBudget
        self.categoryBudget = categoryBudget
        let editingCategory = categoryBudget != nil
        let startsWithCategoryBudget = editingCategory || (overallBudgetCreated && mainBudget == nil)
        _scope = State(initialValue: startsWithCategoryBudget ? .category : .overall)
        _selectedCategoryID = State(initialValue: categoryBudget?.categoryID)
        _period = State(initialValue: Self.timeFrame(for: mainBudget?.periodType ?? categoryBudget?.periodType ?? .week))
        let amountMinor = mainBudget?.amountMinor ?? categoryBudget?.amountMinor ?? 0
        _amountText = State(initialValue: Self.amountString(minor: amountMinor, exponent: mainBudget?.currencyExponent ?? categoryBudget?.currencyExponent ?? 2))
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
        .alert(AppLocalization.key("budget.saveErrorTitle"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(AppLocalization.key("action.ok"), role: .cancel) {}
        } message: { Text(verbatim: errorMessage ?? AppLocalization.string("budget.saveError")) }
    }

    private var exponent: Int { mainBudget?.currencyExponent ?? categoryBudget?.currencyExponent ?? 2 }
    private var parsedMinor: Int64? {
        guard let value = BudgetAmountParser.decimal(from: amountText), BudgetAmountParser.isValid(value) else { return nil }
        return NSDecimalNumber(decimal: value).multiplying(by: NSDecimalNumber(value: pow(10.0, Double(exponent)))).int64Value
    }

    private func save() {
        guard let amountMinor = parsedMinor else { return }
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
                errorMessage = AppLocalization.string("budget.saveError")
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
