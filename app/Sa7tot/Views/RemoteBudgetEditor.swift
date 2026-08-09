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
                Section("Tipo di budget") {
                    Picker("Ambito", selection: $scope) {
                        Text("Budget complessivo").tag(RemoteBudgetScope.overall)
                        Text("Budget per categoria").tag(RemoteBudgetScope.category)
                    }
                    .disabled(overallBudgetCreated || mainBudget != nil || categoryBudget != nil)
                    if scope == .category {
                        Picker("Categoria", selection: $selectedCategoryID) {
                            Text("Seleziona una categoria").tag(UUID?.none)
                            ForEach(store.categories.filter { !$0.income }) { category in
                                Text(category.name).tag(Optional(category.id))
                            }
                        }
                    }
                }
                Section("Periodo") {
                    Picker("Frequenza", selection: $period) {
                        Text("Giornaliero").tag(BudgetTimeFrame.day)
                        Text("Settimanale").tag(BudgetTimeFrame.week)
                        Text("Mensile").tag(BudgetTimeFrame.month)
                        Text("Annuale").tag(BudgetTimeFrame.year)
                    }
                }
                Section("Importo") {
                    TextField("0,00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle("Nuovo budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .disabled(isSaving || parsedMinor == nil || (scope == .category && selectedCategoryID == nil))
                }
            }
        }
        .presentationDetents([.fraction(0.74), .large])
        .presentationDragIndicator(.visible)
        .alert("Impossibile salvare il budget", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "Riprova più tardi.") }
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
                errorMessage = "Impossibile salvare il budget. Riprova."
                isSaving = false
            }
        }
    }

    private static func timeFrame(for period: RemoteBudgetPeriod) -> BudgetTimeFrame {
        switch period { case .day: .day; case .week: .week; case .month: .month; case .year: .year }
    }

    private static func amountString(minor: Int64, exponent: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = exponent
        formatter.maximumFractionDigits = exponent
        let value = NSDecimalNumber(mantissa: UInt64(abs(minor)), exponent: Int16(-exponent), isNegative: false)
        return formatter.string(from: value) ?? "0"
    }
}
