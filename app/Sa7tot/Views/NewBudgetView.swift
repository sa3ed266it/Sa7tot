//
//  NewBudgetView.swift
//  Sa7tot
//

import CoreData
import SwiftUI
import UIKit
import WidgetKit

struct InstructionHeadings {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
}

private enum BudgetCreationStep: Hashable {
    case period
    case amount
}

private enum BudgetScope: String, CaseIterable, Identifiable {
    case overall
    case category

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overall: "Budget complessivo"
        case .category: "Budget per categoria"
        }
    }
    var subtitle: String {
        switch self {
        case .overall: "Tutte le spese"
        case .category: "Una categoria specifica"
        }
    }
}

private struct BudgetCreationDraft {
    var scope: BudgetScope = .overall
    var category: Category?
    var period: BudgetTimeFrame = .week
    var amount: Decimal = 0
    var currencyCode: String
    var computedStartDate: Date = Date.now

    init(currencyCode: String) {
        self.currencyCode = currencyCode
    }
}

struct BrandNewBudgetView: View {
    let overallBudgetCreated: Bool
    let toEditBudget: Budget?
    let toEditMainBudget: MainBudget?

    init(overallBudgetCreated: Bool, toEditBudget: Budget? = nil, toEditMainBudget: MainBudget? = nil) {
        self.overallBudgetCreated = overallBudgetCreated
        self.toEditBudget = toEditBudget
        self.toEditMainBudget = toEditMainBudget
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NativeBrandNewBudgetView(
                overallBudgetCreated: overallBudgetCreated,
                toEditBudget: toEditBudget,
                toEditMainBudget: toEditMainBudget
            )
        } else {
            NavigationView {
                Form {
                    Section {
                        Text("La creazione del budget richiede i controlli nativi disponibili da iOS 16.")
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Nuovo budget")
            }
        }
    }
}

@available(iOS 16.0, *)
private struct NativeBrandNewBudgetView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.order, ascending: true)],
        predicate: NSPredicate(format: "income == NO")
    ) private var categories: FetchedResults<Category>

    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
    private var currencyCode = Locale.current.currencyCode ?? "EUR"

    @State private var path: [BudgetCreationStep] = []
    @State private var draft: BudgetCreationDraft
    @State private var amountText = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var saveSucceeded = false
    @FocusState private var amountFieldFocused: Bool

    let overallBudgetCreated: Bool
    let toEditBudget: Budget?
    let toEditMainBudget: MainBudget?

    private var isEditing: Bool { toEditBudget != nil || toEditMainBudget != nil }
    private var stepNumber: Int { path.count + 1 }
    private var parsedAmount: Decimal? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter.number(from: amountText)?.decimalValue
    }
    private var currentAmount: Decimal { parsedAmount ?? draft.amount }
    private var stepIsValid: Bool {
        switch stepNumber {
        case 1: draft.scope == .overall || draft.category != nil
        case 2: true
        default: currentAmount > 0 && draft.currencyCode.isEmpty == false
        }
    }

    init(overallBudgetCreated: Bool, toEditBudget: Budget? = nil, toEditMainBudget: MainBudget? = nil) {
        self.overallBudgetCreated = overallBudgetCreated
        self.toEditBudget = toEditBudget
        self.toEditMainBudget = toEditMainBudget

        let code = UserDefaults(suiteName: "group.com.saied.sa7tot")?.string(forKey: "currency")
            ?? Locale.current.currencyCode
            ?? "EUR"
        _draft = State(initialValue: BudgetCreationDraft(currencyCode: code))
    }

    var body: some View {
        NavigationStack(path: $path) {
            stepView
                .navigationTitle("Nuovo budget")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .navigationDestination(for: BudgetCreationStep.self) { step in
                    switch step {
                    case .period:
                        periodStep
                    case .amount:
                        amountStep
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .alert("Impossibile salvare il budget", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
        .onAppear(perform: loadDraft)
    }

    @ViewBuilder
    private var stepView: some View {
        scopeStep
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if path.isEmpty {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Annulla") { dismiss() }
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button(path.count == 2 ? "Crea" : "Avanti") {
                advanceOrSave()
            }
            .disabled(!stepIsValid)
        }
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Passaggio \(stepNumber) di 3")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(stepNumber), total: 3)
                .progressViewStyle(.linear)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Passaggio \(stepNumber) di 3")
    }

    private var scopeStep: some View {
        Form {
            Section { progressView }
            Section {
                Text("Che cosa vuoi monitorare?")
                    .font(.headline)
                Text("Scegli se controllare tutte le spese oppure una categoria specifica.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("TIPO DI BUDGET") {
                ForEach(BudgetScope.allCases) { scope in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            draft.scope = scope
                            if scope == .overall { draft.category = nil }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scope.title)
                                Text(scope.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if draft.scope == scope {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }

            if draft.scope == .category {
                Section("CATEGORIA") {
                    ForEach(categories, id: \.objectID) { category in
                        Button {
                            draft.category = category
                        } label: {
                            HStack(spacing: 12) {
                                CategoryIconView(
                                    descriptor: category.iconDescriptor,
                                    role: .inline,
                                    accessibilityLabel: category.wrappedName
                                )
                                Text(category.wrappedName)
                                Spacer()
                                if draft.category?.objectID == category.objectID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .formStyle(.automatic)
    }

    private var periodStep: some View {
        Form {
            Section { progressView }
            Section {
                Text("Con quale frequenza?")
                    .font(.headline)
                Text("Il budget si rinnova automaticamente in base al periodo scelto.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("PERIODO") {
                Picker("Periodo", selection: $draft.period) {
                    Text("Giornaliero").tag(BudgetTimeFrame.day)
                    Text("Settimanale").tag(BudgetTimeFrame.week)
                    Text("Mensile").tag(BudgetTimeFrame.month)
                    Text("Annuale").tag(BudgetTimeFrame.year)
                }
                .pickerStyle(.inline)
            }
        }
        .formStyle(.automatic)
        .toolbar { toolbarContent }
    }

    private var amountStep: some View {
        Form {
            Section { progressView }
            Section {
                Text("Quanto vuoi spendere?")
                    .font(.headline)
                Text("Inserisci il limite del budget. Potrai modificarlo in seguito.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("IMPORTO") {
                TextField("Importo", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($amountFieldFocused)
                    .onChange(of: amountText) { value in
                        if let value = decimalValue(from: value) { draft.amount = value }
                    }
                LabeledContent("Valuta") {
                    Text(draft.currencyCode)
                        .foregroundStyle(.secondary)
                }
            }
            Section("RIEPILOGO") {
                LabeledContent("Tipo") {
                    Text(draft.scope == .overall ? "Budget complessivo" : "Budget per categoria")
                        .foregroundStyle(.secondary)
                }
                if draft.scope == .category, let category = draft.category {
                    LabeledContent("Categoria") {
                        Text(category.wrappedName)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Periodo") {
                    Text(periodTitle)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Inizio") {
                    Text(startDateString)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Valuta") {
                    Text(draft.currencyCode)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.automatic)
        .toolbar { toolbarContent }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fine") { amountFieldFocused = false }
            }
        }
    }

    private var periodTitle: String {
        switch draft.period {
        case .day: "Giornaliero"
        case .week: "Settimanale"
        case .month: "Mensile"
        case .year: "Annuale"
        }
    }

    private var computedStartDate: Date {
        let now = Date.now
        switch draft.period {
        case .day:
            return Calendar.current.startOfDay(for: now)
        case .week:
            return Sa7totCalendarSettings.startOfWeek(for: now)
        case .month:
            return Sa7totCalendarSettings.startOfMonth(for: now)
        case .year:
            let calendar = Calendar.current
            return calendar.date(from: calendar.dateComponents([.year], from: now)) ?? calendar.startOfDay(for: now)
        }
    }

    private var startDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: computedStartDate)
    }

    private func decimalValue(from string: String) -> Decimal? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter.number(from: string)?.decimalValue
    }

    private func advanceOrSave() {
        guard stepIsValid else { return }
        draft.computedStartDate = computedStartDate

        if path.count == 0 {
            path.append(.period)
        } else if path.count == 1 {
            path.append(.amount)
        } else {
            saveDraft()
        }
    }

    private func loadDraft() {
        guard isEditing else {
            draft.currencyCode = currencyCode
            return
        }

        if let budget = toEditBudget {
            draft.scope = .category
            draft.category = budget.category
            draft.period = BudgetTimeFrame(rawValue: budgetType(for: budget.type)) ?? .week
            draft.amount = Decimal(budget.amount)
        } else if let budget = toEditMainBudget {
            draft.scope = .overall
            draft.period = BudgetTimeFrame(rawValue: budgetType(for: budget.type)) ?? .week
            draft.amount = Decimal(budget.amount)
        }
        draft.currencyCode = currencyCode
        amountText = decimalString(draft.amount)
        path = [.period, .amount]
    }

    private func budgetType(for rawValue: Int16) -> String {
        switch rawValue {
        case 1: "Daily"
        case 2: "Weekly"
        case 3: "Monthly"
        case 4: "Yearly"
        default: "Weekly"
        }
    }

    private func decimalString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }

    private func saveDraft() {
        guard currentAmount > 0,
              draft.scope == .overall || draft.category != nil else { return }

        let startDate = computedStartDate
        let type = Int16(budgetType(for: draft.period))

        do {
            if let budget = toEditBudget {
                budget.category = draft.category
                budget.startDate = startDate
                budget.amount = NSDecimalNumber(decimal: currentAmount).doubleValue
                budget.type = type
            } else if let mainBudget = toEditMainBudget {
                mainBudget.startDate = startDate
                mainBudget.amount = NSDecimalNumber(decimal: currentAmount).doubleValue
                mainBudget.type = type
            } else if draft.scope == .category, let category = draft.category {
                let budget = Budget(context: moc)
                budget.category = category
                budget.startDate = startDate
                budget.amount = NSDecimalNumber(decimal: currentAmount).doubleValue
                budget.dateCreated = Date.now
                budget.type = type
                budget.id = UUID()
            } else {
                let budget = MainBudget(context: moc)
                budget.startDate = startDate
                budget.amount = NSDecimalNumber(decimal: currentAmount).doubleValue
                budget.type = type
            }

            try moc.save()
            WidgetCenter.shared.reloadAllTimelines()
            saveSucceeded.toggle()
            dismiss()
        } catch {
            moc.rollback()
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }

    private func budgetType(for period: BudgetTimeFrame) -> Int {
        switch period {
        case .day: 1
        case .week: 2
        case .month: 3
        case .year: 4
        }
    }
}
