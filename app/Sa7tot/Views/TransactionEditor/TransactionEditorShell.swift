import CoreData
import SwiftUI

struct TransactionEditorShell: View {
    let isEditing: Bool
    @Binding var isTransfer: Bool
    @Binding var income: Bool
    @Binding var price: Double
    @Binding var isEditingDecimal: Bool
    @Binding var decimalValuesAssigned: AssignedDecimal
    @Binding var note: String
    @Binding var category: Category?
    @Binding var account: Account?
    @Binding var destinationAccount: Account?
    @Binding var date: Date
    @Binding var repeatType: Int
    @Binding var repeatCoefficient: Int
    let currencySymbol: String
    let suggestedTransactions: [Transaction]
    let showRecommendations: Bool
    let onSave: () -> Void
    let onDismiss: () -> Void
    let onDeleteConfirmed: () -> Void

    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showCategorySheet = false
    @State private var showCustomRecurring = false
    @State private var showNoteSheet = false
    @State private var showDeleteConfirmation = false
    @State private var noteDraft = ""
    @State private var amountText = ""
    @FocusState private var amountFocused: Bool

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "order", ascending: true)])
    private var accounts: FetchedResults<Account>

    private var canSave: Bool {
        guard price.isFinite, price > 0 else { return false }
        if isTransfer { return account != nil && destinationAccount != nil && account != destinationAccount }
        return category != nil
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: price)) ?? "0,00"
    }

    private var typeSelection: Binding<String> {
        Binding(
            get: { isTransfer ? "transfer" : (income ? "income" : "expense") },
            set: { value in
                guard !(isEditing && isTransfer) else { return }
                guard value != "transfer" || !isEditing else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isTransfer = value == "transfer"
                    income = value == "income"
                    if isTransfer {
                        category = nil
                        repeatType = 0
                        repeatCoefficient = 1
                        showCustomRecurring = false
                        destinationAccount = accounts.first(where: { $0 != account && !$0.isArchived })
                    } else {
                        category = nil
                        if value == "income" {
                            repeatType = 0
                            repeatCoefficient = 1
                            showCustomRecurring = false
                        }
                        if destinationAccount == account { destinationAccount = nil }
                    }
                }
            }
        )
    }

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack { editorContent }
            } else {
                NavigationView { editorContent }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility5)
        .onChange(of: account) { newSource in
            if newSource == destinationAccount {
                destinationAccount = accounts.first(where: { $0 != newSource && !$0.isArchived })
            }
        }
        .onChange(of: destinationAccount) { newDestination in
            if newDestination == account { destinationAccount = nil }
        }
        .onAppear {
            if amountText.isEmpty { amountText = inputAmount(for: price) }
        }
        .onChange(of: price) { newPrice in
            if !amountFocused { amountText = inputAmount(for: newPrice) }
        }
        .onChange(of: amountFocused) { focused in
            if focused && price == 0 { amountText = "" }
            if !focused && amountText.isEmpty { amountText = inputAmount(for: price) }
        }
    }

    private var editorContent: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    typeSelector
                    amountSection
                    if !isTransfer { categoryCarousel }
                    suggestionsSection
                    detailsSection
                    deleteSection
                }
                .padding(.horizontal, 17)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .navigationTitle(isEditing ? (isTransfer ? "Modifica trasferimento" : "Modifica movimento") : "Nuovo movimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", action: onSave)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fine") {
                        amountFocused = false
                        UIApplication.shared.endEditing()
                    }
                    .accessibilityLabel("Fine modifica importo")
                }
            }
            .confirmationDialog(
                isTransfer ? "Eliminare questo trasferimento?" : "Eliminare questo movimento?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Elimina", role: .destructive, action: onDeleteConfirmed)
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Questa azione non può essere annullata.")
            }
            .sheet(isPresented: $showCategorySheet) {
                CategoryView(mode: .transaction, income: income)
            }
            .sheet(isPresented: $showCustomRecurring) {
                TransactionEditorCustomRecurrenceSheet(
                    repeatType: $repeatType,
                    repeatCoefficient: $repeatCoefficient,
                    isPresented: $showCustomRecurring
                )
            }
            .sheet(isPresented: $showNoteSheet, onDismiss: {
                noteDraft = note
            }) {
                TransactionEditorNoteSheet(
                    note: $note,
                    draft: $noteDraft,
                    price: $price,
                    category: $category,
                    suggestedTransactions: suggestedTransactions,
                    currencySymbol: currencySymbol,
                    showRecommendations: showRecommendations,
                    isPresented: $showNoteSheet
                )
            }
    }

    @ViewBuilder private var typeSelector: some View {
        if isEditing && isTransfer {
            Text("Trasferimento")
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Tipo di movimento: Trasferimento")
        } else {
            Picker("Tipo di movimento", selection: typeSelection) {
                Text("Spesa").tag("expense")
                Text("Entrata").tag("income")
                if !isEditing { Text("Trasferimento").tag("transfer") }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Tipo di movimento")
        }
    }

    private var amountSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(currencySymbol)
                    .font(.system(size: dynamicTypeSize >= .xxLarge ? 42 : 48, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("0,00", text: amountTextBinding)
                    .focused($amountFocused)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .font(.system(size: dynamicTypeSize >= .xxLarge ? 64 : 80, weight: .regular, design: .rounded))
                    .minimumScaleFactor(0.42)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .submitLabel(.done)
                    .accessibilityLabel("Importo")
                    .accessibilityValue(currencySymbol + (amountText.isEmpty ? formattedAmount : amountText))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { amountFocused = true }
        }
        .padding(.vertical, 4)
    }

    private var amountTextBinding: Binding<String> {
        Binding(
            get: { amountText },
            set: { newValue in
                let clampedValue = clampedAmountText(newValue)
                amountText = clampedValue
                if let parsed = parsedAmount(clampedValue) {
                    price = parsed
                } else if clampedValue.isEmpty || clampedValue == "," || clampedValue == "." {
                    price = 0
                }
            }
        )
    }

    private func clampedAmountText(_ value: String) -> String {
        let decimalSeparator = value.firstIndex(of: ",") ?? value.firstIndex(of: ".")
        guard let decimalSeparator else { return value }
        let fractionStart = value.index(after: decimalSeparator)
        let fraction = value[fractionStart...]
        guard fraction.count > 2 else { return value }
        return String(value[..<value.index(fractionStart, offsetBy: 2)])
    }

    private func parsedAmount(_ value: String) -> Double? {
        let normalized = value
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        guard let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return NSDecimalNumber(decimal: decimal).doubleValue
    }

    private func inputAmount(for value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "0,00"
    }

    @ViewBuilder private var suggestionsSection: some View {
        if showRecommendations && showNoteSheet && !noteDraft.isEmpty && !isEditing && !suggestedTransactions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestedTransactions, id: \.objectID) { transaction in
                        Button {
                            noteDraft = transaction.wrappedNote
                            if price == 0 { price = transaction.wrappedAmount }
                            if category == nil { category = transaction.category }
                        } label: {
                            Text(transaction.wrappedNote + "  " + currencySymbol + String(format: "%.0f", transaction.wrappedAmount))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .accessibilityLabel("Suggerimento " + transaction.wrappedNote)
                    }
                }
            }
        }
    }

    private var detailsSection: some View {
        GroupBox {
            VStack(spacing: 10) {
                TransactionEditorRow(title: "Data e ora", systemImage: "calendar") {
                    DatePicker("Data e ora", selection: $date).labelsHidden().datePickerStyle(.compact)
                }
                if isTransfer {
                    TransactionEditorRow(title: "Da", systemImage: "arrow.up.right") {
                        AccountMenuView(accounts: Array(accounts), account: $account)
                    }
                    TransactionEditorRow(title: "A", systemImage: "arrow.down.left") {
                        AccountMenuView(accounts: Array(accounts), account: $destinationAccount)
                    }
                } else {
                    TransactionEditorRow(title: "Conto", systemImage: "building.columns.fill") {
                        AccountMenuView(accounts: Array(accounts), account: $account)
                    }
                }
                if !isTransfer && !income { recurrenceRow }
                noteRow
            }
        }
    }

    private var categoryCarousel: some View {
        TransactionEditorCategoryCarousel(
            category: $category,
            income: income,
            onManage: { showCategorySheet = true }
        )
    }

    private var recurrenceRow: some View {
        TransactionEditorRow(title: "Ripeti", systemImage: "repeat") {
            Menu {
                recurrenceChoice("Mai", type: 0, coefficient: 1)
                recurrenceChoice("Ogni giorno", type: 1, coefficient: 1)
                recurrenceChoice("Ogni settimana", type: 2, coefficient: 1)
                recurrenceChoice("Ogni mese", type: 3, coefficient: 1)
                Divider()
                Button {
                    showCustomRecurring = true
                } label: {
                    Label("Personalizzata…", systemImage: "slider.horizontal.3")
                }
            } label: {
                HStack(spacing: 5) {
                    Text(repeatSummary)
                        .foregroundStyle(repeatType == 0 ? .secondary : Color.IncomeGreen)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Ripeti")
            .accessibilityValue(repeatSummary)
        }
    }

    private var noteRow: some View {
        TransactionEditorRow(title: "Nota", systemImage: "note.text") {
            HStack(spacing: 8) {
                if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(0)
                }
                Button(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Aggiungi" : "Modifica") {
                    noteDraft = note
                    showNoteSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .layoutPriority(1)
                .accessibilityLabel(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Aggiungi nota" : "Modifica nota")
            }
            .frame(minHeight: 44)
        }
    }

    private func recurrenceChoice(_ title: String, type: Int, coefficient: Int) -> some View {
        Button {
            repeatType = type
            repeatCoefficient = coefficient
        } label: {
            HStack {
                Text(title)
                Spacer()
                if repeatType == type && (type == 0 || repeatCoefficient == coefficient) {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    @ViewBuilder private var deleteSection: some View {
        if isEditing {
            Button(role: .destructive) { showDeleteConfirmation = true } label: {
                Label(isTransfer ? "Elimina trasferimento" : "Elimina movimento", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(isTransfer ? "Elimina trasferimento" : "Elimina movimento")
        }
    }

    private var repeatSummary: String {
        switch repeatType {
        case 1: return "Ogni \(repeatCoefficient) giorno\(repeatCoefficient == 1 ? "" : "i")"
        case 2: return "Ogni \(repeatCoefficient) settiman\(repeatCoefficient == 1 ? "a" : "e")"
        case 3: return "Ogni \(repeatCoefficient) mes\(repeatCoefficient == 1 ? "e" : "i")"
        default: return "Mai"
        }
    }
}

private struct TransactionEditorRow<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            content
        }
        .frame(minHeight: 44)
    }
}

private enum TransactionEditorCategorySymbolResolver {
    private static let symbols: [String: String] = [
        "spesa": "cart.fill",
        "spese": "cart.fill",
        "abbonamenti": "repeat.circle.fill",
        "trasporti": "tram.fill",
        "cibo": "fork.knife",
        "casa": "house.fill",
        "bollette": "bolt.fill",
        "salute": "cross.case.fill",
        "shopping": "bag.fill",
        "svago": "gamecontroller.fill",
        "viaggi": "airplane",
        "regali": "gift.fill",
        "istruzione": "book.fill",
        "sport": "figure.run",
        "animali": "pawprint.fill",
        "stipendio": "banknote.fill",
        "entrate": "arrow.down.circle.fill",
        "reddito": "arrow.down.circle.fill",
        "rimborso": "arrow.uturn.backward.circle.fill",
        "risparmi": "building.columns.fill",
        "altro": "tag.fill"
    ]

    static func symbol(for name: String) -> String {
        let normalized = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return symbols[normalized] ?? "tag.fill"
    }
}

private struct TransactionEditorCategoryCarousel: View {
    @Binding var category: Category?
    let income: Bool
    let onManage: () -> Void
    @FetchRequest private var categories: FetchedResults<Category>

    init(category: Binding<Category?>, income: Bool, onManage: @escaping () -> Void) {
        _category = category
        self.income = income
        self.onManage = onManage
        _categories = FetchRequest<Category>(
            sortDescriptors: [SortDescriptor(\.order, order: .reverse)],
            predicate: NSPredicate(format: "income = %d", income)
        )
    }

    var body: some View {
        Group {
            if categories.isEmpty {
                Button(action: onManage) {
                    Label("Aggiungi categoria", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 14)
                        .background(Color.SecondaryBackground, in: Capsule())
                }
                .accessibilityLabel("Aggiungi categoria")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(categories, id: \.objectID) { item in
                                categoryChip(item)
                                    .id(item.objectID)
                            }
                            Button(action: onManage) {
                                Label("Gestisci", systemImage: "ellipsis.circle")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .frame(minHeight: 44)
                                    .padding(.horizontal, 14)
                                    .background(Color.SecondaryBackground, in: Capsule())
                            }
                            .accessibilityLabel("Gestisci categorie")
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                    }
                    .onAppear {
                        scrollToSelection(using: proxy, animated: false)
                    }
                    .onChange(of: category) { _ in
                        scrollToSelection(using: proxy, animated: true)
                    }
                }
                .frame(minHeight: 52)
            }
        }
    }

    private func categoryChip(_ item: Category) -> some View {
        let selected = item == category
        let tint = Color(hex: item.wrappedColour)
        return Button {
            category = item
        } label: {
            HStack(spacing: 7) {
                Image(systemName: TransactionEditorCategorySymbolResolver.symbol(for: item.wrappedName))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(item.wrappedName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                }
            }
            .font(.body.weight(selected ? .semibold : .regular))
            .frame(minHeight: 44)
            .padding(.horizontal, 13)
            .background(
                selected ? tint.opacity(0.2) : Color.SecondaryBackground,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.wrappedName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func scrollToSelection(using proxy: ScrollViewProxy, animated: Bool) {
        guard let selected = category, categories.contains(where: { $0 == selected }) else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(selected.objectID, anchor: .center)
            }
        } else {
            proxy.scrollTo(selected.objectID, anchor: .center)
        }
    }
}

private struct TransactionEditorNoteSheet: View {
    @Binding var note: String
    @Binding var draft: String
    @Binding var price: Double
    @Binding var category: Category?
    let suggestedTransactions: [Transaction]
    let currencySymbol: String
    let showRecommendations: Bool
    @Binding var isPresented: Bool
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Aggiungi una nota")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $draft)
                        .focused($focused)
                        .font(.body)
                        .frame(minHeight: 130, maxHeight: 150)
                        .padding(4)
                        .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: draft) { value in
                            if value.count > 50 { draft = String(value.prefix(50)) }
                        }
                        .accessibilityLabel("Nota")
                }
                if showRecommendations && !draft.isEmpty && !suggestedTransactions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestedTransactions, id: \.objectID) { transaction in
                                Button {
                                    draft = transaction.wrappedNote
                                    if price == 0 { price = transaction.wrappedAmount }
                                    if category == nil { category = transaction.category }
                                } label: {
                                    Text(transaction.wrappedNote + "  " + currencySymbol + String(format: "%.0f", transaction.wrappedAmount))
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .navigationTitle("Nota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        note = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            focused = true
        }
        .modifier(TransactionEditorNoteSheetPresentation())
    }
}

private struct TransactionEditorNoteSheetPresentation: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

private struct TransactionEditorCustomRecurrenceSheet: View {
    @Binding var repeatType: Int
    @Binding var repeatCoefficient: Int
    @Binding var isPresented: Bool
    @State private var unit = 1
    @State private var coefficient = 1

    private var unitLabel: String {
        switch unit {
        case 2: return coefficient == 1 ? "settimana" : "settimane"
        case 3: return coefficient == 1 ? "mese" : "mesi"
        default: return coefficient == 1 ? "giorno" : "giorni"
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Picker("Unità", selection: $unit) {
                    Text("Giorni").tag(1)
                    Text("Settimane").tag(2)
                    Text("Mesi").tag(3)
                }
                Stepper(value: $coefficient, in: 1...99) {
                    Text("Ogni \(coefficient) \(unitLabel)")
                }
            }
            .navigationTitle("Personalizzata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        repeatType = unit
                        repeatCoefficient = coefficient
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            unit = repeatType == 0 ? 1 : repeatType
            coefficient = max(1, repeatCoefficient)
        }
        .modifier(TransactionEditorCustomRecurrencePresentation())
    }
}

private struct TransactionEditorCustomRecurrencePresentation: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
        } else if #available(iOS 16.0, *) {
            content
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}
