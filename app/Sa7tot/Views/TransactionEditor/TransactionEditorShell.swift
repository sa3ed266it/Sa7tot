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
    @State private var showCategoryPicker = false
    @State private var showCategorySheet = false
    @State private var showRecurring = false
    @State private var showRecurringPicker = false
    @State private var showDeleteConfirmation = false
    @State private var noteFocused = false

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
                        destinationAccount = accounts.first(where: { $0 != account && !$0.isArchived })
                    } else {
                        category = nil
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
    }

    private var editorContent: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    typeSelector
                    amountSection
                    suggestionsSection
                    detailsSection
                    deleteSection
                }
                .padding(.horizontal, 17)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TransactionEditorKeypad(
                    price: $price,
                    isEditingDecimal: $isEditingDecimal,
                    decimalValuesAssigned: $decimalValuesAssigned,
                    showingNotePicker: noteFocused
                )
                .frame(maxHeight: 255)
                .padding(.horizontal, 17)
                .padding(.top, 8)
                .background(.regularMaterial)
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
            .sheet(isPresented: $showCategoryPicker) {
                NewCategoryPickerView(
                    category: $category,
                    showPicker: $showCategoryPicker,
                    showSheet: $showCategorySheet,
                    income: income
                )
                .environment(\.managedObjectContext, moc)
            }
            .sheet(isPresented: $showCategorySheet) {
                CategoryView(mode: .transaction, income: income)
            }
            .sheet(isPresented: $showRecurring) {
                recurringPickerContent
            }
    }

    @ViewBuilder private var recurringPickerContent: some View {
        if #available(iOS 16.0, *) {
            RecurringPickerView(
                repeatType: $repeatType,
                repeatCoefficient: $repeatCoefficient,
                showMenu: $showRecurring,
                showPicker: $showRecurringPicker
            )
            .presentationDetents([.height(250)])
        } else {
            RecurringPickerView(
                repeatType: $repeatType,
                repeatCoefficient: $repeatCoefficient,
                showMenu: $showRecurring,
                showPicker: $showRecurringPicker
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
            Text(currencySymbol + formattedAmount)
                .font(.system(size: dynamicTypeSize >= .xxLarge ? 48 : 56, weight: .regular, design: .rounded))
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Importo")
                .accessibilityValue(currencySymbol + formattedAmount)
            TransactionEditorNoteField(note: $note, focused: $noteFocused)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var suggestionsSection: some View {
        if showRecommendations && noteFocused && !note.isEmpty && !isEditing && !suggestedTransactions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestedTransactions, id: \.objectID) { transaction in
                        Button {
                            note = transaction.wrappedNote
                            if price == 0 { price = transaction.wrappedAmount }
                            if category == nil { category = transaction.category }
                            noteFocused = false
                            UIApplication.shared.endEditing()
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
                if !isTransfer { categoryRow }
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
                if !isTransfer { recurrenceRow }
            }
        }
    }

    private var categoryRow: some View {
        TransactionEditorRow(title: "Categoria", systemImage: "circle.grid.2x2") {
            Button { showCategoryPicker = true } label: {
                if let category {
                    Text(category.wrappedEmoji + " " + category.wrappedName)
                        .foregroundStyle(Color(hex: category.wrappedColour)).lineLimit(1)
                } else {
                    Text("Scegli").foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Categoria")
        }
    }

    private var recurrenceRow: some View {
        TransactionEditorRow(title: "Ripeti", systemImage: "repeat") {
            Button { showRecurring = true } label: {
                Text(repeatSummary).foregroundStyle(repeatType == 0 ? .secondary : Color.IncomeGreen)
            }
            .accessibilityLabel(repeatType == 0 ? "Ripeti, disattivato" : repeatSummary)
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

private struct TransactionEditorNoteField: View {
    @Binding var note: String
    @Binding var focused: Bool
    @FocusState private var textFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.alignleft")
                .foregroundStyle(.secondary)
            TextField("Aggiungi nota", text: $note)
                .focused($textFocused)
                .onChange(of: textFocused) { focused = $0 }
                .onChange(of: note) { value in
                    if value.count > 50 { note = String(value.prefix(50)) }
                }
                .accessibilityLabel("Nota")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { textFocused = true }
    }
}
