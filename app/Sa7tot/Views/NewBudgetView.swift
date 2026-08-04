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

private enum BudgetFlowStyle {
    static let horizontalPadding: CGFloat = 20
    static let headingTopPadding: CGFloat = 24
    static let sectionTopPadding: CGFloat = 24
    static let cardCornerRadius: CGFloat = 18
    static let iconTileSize: CGFloat = 40
}

private extension View {
    @ViewBuilder
    func budgetGlassSurface<S: Shape>(isSelected: Bool, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(
                .regular
                    .interactive()
                    .tint(isSelected ? .accentColor : nil),
                in: shape
            )
        } else {
            background(.thinMaterial, in: shape)
                .overlay {
                    shape.stroke(
                        isSelected ? AnyShapeStyle(.tint.opacity(0.65)) : AnyShapeStyle(Color.Outline.opacity(0.7)),
                        lineWidth: 1
                    )
                }
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
    @State private var isSaving = false
    @State private var showCategoryCreation = false
    @State private var categoryCreationIsIncome = false
    @State private var selectedSheetDetent: PresentationDetent = .fraction(0.74)
    @FocusState private var amountFieldFocused: Bool

    let overallBudgetCreated: Bool
    let toEditBudget: Budget?
    let toEditMainBudget: MainBudget?

    private var isEditing: Bool { toEditBudget != nil || toEditMainBudget != nil }
    private var activeExpenseCategories: [Category] {
        categories.filter { !$0.isDeleted && $0.managedObjectContext != nil }
    }
    private var stepNumber: Int { path.count + 1 }
    private var parsedAmount: Decimal? {
        BudgetAmountParser.decimal(from: amountText)
    }
    private var stepIsValid: Bool {
        switch stepNumber {
        case 1:
            return draft.scope == .overall || draft.category != nil
        case 2:
            return true
        default:
            guard let amount = parsedAmount else { return false }
            return BudgetAmountParser.isValid(amount) && draft.currencyCode.isEmpty == false && !isSaving
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
        Group {
            if #available(iOS 26.0, *) {
                navigationContent
            } else if #available(iOS 16.4, *) {
                navigationContent
                    .presentationBackground(.ultraThinMaterial)
            } else {
                navigationContent
            }
        }
        .presentationDetents([.fraction(0.74), .large], selection: $selectedSheetDetent)
        .presentationDragIndicator(.visible)
        .alert("Impossibile salvare il budget", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
        .sheet(isPresented: $showCategoryCreation) {
            NewCategoryAlert(income: $categoryCreationIsIncome, bottomSpacers: false, budgetMode: true)
                .presentationDetents([.fraction(0.47)])
        }
        .onAppear(perform: loadDraft)
        .onChange(of: amountFieldFocused) { focused in
            selectedSheetDetent = focused ? .large : .fraction(0.74)
        }
    }

    private var navigationContent: some View {
        ZStack {
            budgetFlowSharedBackdrop

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
        }
    }

    private var budgetFlowSharedBackdrop: some View {
        (colorScheme == .dark ? Color.black : Color.white)
            .opacity(0.14)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var stepView: some View {
        scopeStep
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if path.isEmpty {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annulla") { dismiss() }
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button(path.count == 2 ? "Crea" : "Avanti") {
                advanceOrSave()
            }
            .disabled(!stepIsValid)
        }
    }

    private var progressView: some View {
        HStack(spacing: 12) {
            ProgressView(value: Double(stepNumber), total: 3)
                .progressViewStyle(.linear)
            Text("\(stepNumber) di 3")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Passaggio \(stepNumber) di 3")
    }

    private var scopeStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                progressView
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Che cosa vuoi monitorare?")
                        .font(.title2.weight(.semibold))
                    Text("Scegli se controllare tutte le spese oppure una categoria specifica.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, BudgetFlowStyle.headingTopPadding)

                Text("TIPO DI BUDGET")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, BudgetFlowStyle.sectionTopPadding)
                    .padding(.bottom, 12)

                budgetGlassGroup {
                    VStack(spacing: 12) {
                        ForEach(BudgetScope.allCases) { scope in
                            scopeSelectionCard(scope)
                        }
                    }
                }

                if draft.scope == .category {
                    categorySelection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, BudgetFlowStyle.horizontalPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func scopeSelectionCard(_ scope: BudgetScope) -> some View {
        let isSelected = draft.scope == scope

        return Button {
            withAnimation(.snappy) {
                draft.scope = scope
                if scope == .overall { draft.category = nil }
            }
        } label: {
            HStack(spacing: 14) {
                budgetIconTile(
                    systemName: scope == .overall ? "chart.pie.fill" : "tag.fill",
                    isSelected: isSelected
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(scope.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(scope.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                ZStack {
                    if isSelected {
                        Circle()
                            .fill(.tint)
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                    } else {
                        Circle()
                            .stroke(.secondary, lineWidth: 1.5)
                    }
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 76)
            .frame(maxWidth: .infinity, alignment: .leading)
            .budgetGlassSurface(isSelected: isSelected, in: RoundedRectangle(cornerRadius: BudgetFlowStyle.cardCornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(scope.title), \(scope.subtitle)")
        .accessibilityValue(isSelected ? "Selezionato" : "Non selezionato")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var categorySelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CATEGORIA")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, BudgetFlowStyle.sectionTopPadding)

            if activeExpenseCategories.isEmpty {
                Button {
                    categoryCreationIsIncome = false
                    showCategoryCreation = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nessuna categoria disponibile")
                                .font(.subheadline.weight(.semibold))
                            Text("Aggiungi categoria")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.tint)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 60)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .budgetGlassSurface(isSelected: false, in: RoundedRectangle(cornerRadius: BudgetFlowStyle.cardCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Nessuna categoria disponibile. Aggiungi categoria")
            } else {
                budgetGlassGroup {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(activeExpenseCategories, id: \.objectID) { category in
                                budgetCategoryChip(category)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .frame(minHeight: 52)
                }
            }
        }
    }

    private func budgetCategoryChip(_ category: Category) -> some View {
        let isSelected = draft.category?.objectID == category.objectID

        return Button {
            withAnimation(.snappy) {
                draft.category = category
            }
        } label: {
            HStack(spacing: 9) {
                CategoryIconView(
                    descriptor: category.iconDescriptor,
                    role: .inline,
                    accessibilityLabel: category.wrappedName
                )
                Text(category.wrappedName)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 15)
            .frame(minHeight: 44)
            .budgetGlassSurface(isSelected: isSelected, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.wrappedName)
        .accessibilityValue(isSelected ? "Selezionata" : "Non selezionata")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var periodStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                progressView
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Con quale frequenza?")
                        .font(.title2.weight(.semibold))
                    Text("Scegli ogni quanto si rinnova il budget.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, BudgetFlowStyle.headingTopPadding)

                Text("PERIODO")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, BudgetFlowStyle.sectionTopPadding)
                    .padding(.bottom, 12)

                budgetGlassGroup {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(BudgetTimeFrame.allCases, id: \.self) { period in
                            periodSelectionCard(period)
                        }
                    }
                }
            }
            .padding(.horizontal, BudgetFlowStyle.horizontalPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Nuovo budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { periodToolbarContent }
    }

    @ToolbarContentBuilder
    private var periodToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Avanti") {
                advanceOrSave()
            }
            .disabled(!stepIsValid)
        }
    }

    private func periodSelectionCard(_ period: BudgetTimeFrame) -> some View {
        let isSelected = draft.period == period

        return Button {
            withAnimation(.snappy) {
                draft.period = period
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    budgetIconTile(systemName: "calendar", isSelected: isSelected)

                    Spacer(minLength: 4)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(periodTitle(for: period))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(periodSubtitle(for: period))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .contentShape(Rectangle())
            .budgetGlassSurface(isSelected: isSelected, in: RoundedRectangle(cornerRadius: BudgetFlowStyle.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(periodTitle(for: period))
        .accessibilityValue(isSelected ? "Selezionato" : "Non selezionato")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func periodTitle(for period: BudgetTimeFrame) -> String {
        switch period {
        case .day: "Giornaliero"
        case .week: "Settimanale"
        case .month: "Mensile"
        case .year: "Annuale"
        }
    }

    private func periodSubtitle(for period: BudgetTimeFrame) -> String {
        switch period {
        case .day: "Ogni giorno"
        case .week: "Ogni settimana"
        case .month: "Ogni mese"
        case .year: "Ogni anno"
        }
    }

    private func budgetIconTile(systemName: String, isSelected: Bool) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.accentColor))
            .frame(width: BudgetFlowStyle.iconTileSize, height: BudgetFlowStyle.iconTileSize)
            .background(
                isSelected ? AnyShapeStyle(Color.black.opacity(0.16)) : AnyShapeStyle(Color.accentColor.opacity(0.10)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }

    @ViewBuilder
    private func budgetGlassGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                content()
            }
        } else {
            content()
        }
    }

    private var amountStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                progressView
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quanto vuoi spendere?")
                        .font(.title2.weight(.semibold))
                    Text("Inserisci il limite del budget.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, BudgetFlowStyle.headingTopPadding)

                amountEntry
                    .padding(.top, 36)

                Divider()
                    .padding(.top, 36)

                inlineBudgetSummary
                    .padding(.top, 22)
            }
            .padding(.horizontal, BudgetFlowStyle.horizontalPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Nuovo budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { amountToolbarContent }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fine") { amountFieldFocused = false }
            }
        }
    }

    @ToolbarContentBuilder
    private var amountToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Crea") {
                saveDraft()
            }
            .disabled(!stepIsValid)
        }
    }

    private var amountEntry: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(currencySymbol)
                .font(.title.weight(.regular))
                .foregroundStyle(.secondary)

            TextField("0,00", text: $amountText)
                .font(.largeTitle.weight(.regular))
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .multilineTextAlignment(.center)
                .focused($amountFieldFocused)
                .onChange(of: amountText) { value in
                    if let value = BudgetAmountParser.decimal(from: value) {
                        draft.amount = value
                    }
                }
                .accessibilityLabel("Importo in \(draft.currencyCode)")
                .accessibilityValue(amountText.isEmpty ? "Vuoto" : amountText)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { amountFieldFocused = true }
        .overlay(alignment: .bottom) {
            Text(periodAmountSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .offset(y: 30)
                .allowsHitTesting(false)
        }
    }

    private var inlineBudgetSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RIEPILOGO")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                summaryIcon
                    .frame(width: BudgetFlowStyle.iconTileSize, height: BudgetFlowStyle.iconTileSize)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(summaryPrimary)
                        .font(.body.weight(.semibold))
                    Text(summarySecondary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Riepilogo: \(summaryPrimary), \(summarySecondary)")
    }

    @ViewBuilder
    private var summaryIcon: some View {
        if let category = draft.category, draft.scope == .category {
            CategoryIconView(
                descriptor: category.iconDescriptor,
                role: .inline,
                accessibilityLabel: category.wrappedName
            )
        } else {
            Image(systemName: "chart.pie.fill")
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
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

    private var periodAmountSubtitle: String {
        switch draft.period {
        case .day: "Importo giornaliero"
        case .week: "Importo settimanale"
        case .month: "Importo mensile"
        case .year: "Importo annuale"
        }
    }

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = draft.currencyCode
        return formatter.currencySymbol ?? draft.currencyCode
    }

    private var summaryPrimary: String {
        draft.scope == .overall ? "Budget complessivo" : (draft.category?.wrappedName ?? "Budget per categoria")
    }

    private var summarySecondary: String {
        "\(periodTitle) · dal \(startDateString)"
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
        guard !isSaving,
              let amount = parsedAmount,
              BudgetAmountParser.isValid(amount),
              draft.scope == .overall || draft.category != nil else { return }

        isSaving = true

        let startDate = computedStartDate
        let type = Int16(budgetType(for: draft.period))

        do {
            if let budget = toEditBudget {
                budget.category = draft.category
                budget.startDate = startDate
                budget.amount = NSDecimalNumber(decimal: amount).doubleValue
                budget.type = type
            } else if let mainBudget = toEditMainBudget {
                mainBudget.startDate = startDate
                mainBudget.amount = NSDecimalNumber(decimal: amount).doubleValue
                mainBudget.type = type
            } else if draft.scope == .category, let category = draft.category {
                let budget = Budget(context: moc)
                budget.category = category
                budget.startDate = startDate
                budget.amount = NSDecimalNumber(decimal: amount).doubleValue
                budget.dateCreated = Date.now
                budget.type = type
                budget.id = UUID()
            } else {
                let budget = MainBudget(context: moc)
                budget.startDate = startDate
                budget.amount = NSDecimalNumber(decimal: amount).doubleValue
                budget.type = type
            }

            try moc.save()
            WidgetCenter.shared.reloadAllTimelines()
            saveSucceeded.toggle()
            dismiss()
        } catch {
            moc.rollback()
            isSaving = false
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
