import CoreData
import SwiftUI

struct AccountMenuView: View {
    let accounts: [Account]
    @Binding var account: Account?
    @State private var showingCreateAccount = false

    private var activeAccounts: [Account] {
        AccountQuery.activeAccounts(from: accounts)
    }

    private var selectedAccountName: String {
        account?.name ?? "Seleziona conto"
    }

    var body: some View {
        Group {
            if activeAccounts.isEmpty {
                Button {
                    showingCreateAccount = true
                } label: {
                    Label("Aggiungi conto", systemImage: "plus.circle.fill")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Aggiungi conto")
            } else {
                Menu {
                    ForEach(activeAccounts) { item in
                        Button { account = item } label: {
                            Label(item.name ?? "Account senza nome", systemImage: Sa7totSymbolResolver.resolved(item.iconName ?? "building.columns.fill"))
                        }
                    }
                } label: {
                    Label(selectedAccountName, systemImage: Sa7totSymbolResolver.resolved(account?.iconName ?? "building.columns.fill"))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.PrimaryText)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.AppSecondarySurface, in: RoundedRectangle(cornerRadius: 11.5, style: .continuous))
                }
                .accessibilityLabel("Conto: \(selectedAccountName)")
            }
        }
        .onAppear(perform: synchronizeSelection)
        .onChange(of: accounts.count) { _ in synchronizeSelection() }
        .sheet(isPresented: $showingCreateAccount) {
            if #available(iOS 16.0, *) {
                NavigationStack { AccountEditorView(account: nil) }
            } else {
                NavigationView { AccountEditorView(account: nil) }
            }
        }
    }

    private func synchronizeSelection() {
        guard !activeAccounts.isEmpty else {
            account = nil
            return
        }

        let normalized = AccountQuery.normalizedEditorSelection(current: account, from: activeAccounts)
        if account?.objectID != normalized?.objectID {
            account = normalized
        }
    }
}

struct AccountListView: View {
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var dataController: DataController
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "order", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)])
    private var accounts: FetchedResults<Account>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "order", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)],
        predicate: AccountQuery.activePredicate
    )
    private var activeAccounts: FetchedResults<Account>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)])
    private var transactions: FetchedResults<Transaction>
    @State private var showingEditor = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if activeAccounts.isEmpty {
                AccountEmptyState()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(accounts) { account in
                    NavigationLink {
                        AccountEditorView(account: account)
                    } label: {
                        HStack(spacing: 12) {
                            Sa7totIconTile(
                                systemName: Sa7totSymbolResolver.resolved(account.iconName ?? "building.columns.fill"),
                                tint: Color(hex: account.wrappedColour),
                                size: 34
                            )
                            VStack(alignment: .leading) {
                                Text(account.name ?? "Conto")
                                Text(account.wrappedType.italianName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(accountBalance(account), format: .currency(code: account.currencyCode ?? "EUR"))
                                .font(.subheadline.weight(.semibold))
                        }
                        .opacity(account.isArchived ? 0.5 : 1)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            account.isArchived.toggle()
                            do {
                                try dataController.saveAccountChanges()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        } label: {
                            Label(account.isArchived ? "Riattiva" : "Archivia", systemImage: account.isArchived ? "arrow.uturn.backward" : "archivebox")
                        }
                        .tint(.orange)
                        if account.canDelete {
                            Button(role: .destructive) {
                                moc.delete(account)
                                do {
                                    try dataController.saveAccountChanges()
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            } label: { Label("Elimina", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accountScrollEdgeEffect()
        .navigationTitle("Conti")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingEditor = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nuovo conto")
            }
        }
        .modifier(AccountTabBarVisibilityModifier())
        .sheet(isPresented: $showingEditor) {
            if #available(iOS 16.0, *) {
                NavigationStack { AccountEditorView(account: nil) }
            } else {
                NavigationView { AccountEditorView(account: nil) }
            }
        }
        .alert("Errore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Impossibile salvare le modifiche.")
        }
    }

    private func accountBalance(_ account: Account) -> Double {
        AccountBalanceService.balance(for: account, transactions: transactions)
    }
}

private struct AccountEmptyState: View {
    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                ContentUnavailableView(
                    "Nessun conto",
                    systemImage: "building.columns",
                    description: Text("Tocca + per aggiungere il primo conto.")
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "building.columns")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Nessun conto")
                        .font(.headline)
                    Text("Tocca + per aggiungere il primo conto.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private extension View {
    @ViewBuilder
    func accountScrollEdgeEffect() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

private struct AccountTabBarVisibilityModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .toolbar(.hidden, for: .tabBar)
                .background(AccountTabBarVisibilityBridge())
        } else {
            content
        }
    }
}

private struct AccountTabBarVisibilityBridge: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> AccountTabBarVisibilityController {
        AccountTabBarVisibilityController()
    }

    func updateUIViewController(_ controller: AccountTabBarVisibilityController, context: Context) {
        controller.updateTabBarVisibility()
    }
}

private final class AccountTabBarVisibilityController: UIViewController {
    private weak var tabBarControllerToRestore: UITabBarController?
    private var previousHiddenState = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateTabBarVisibility()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        restoreTabBar()
    }

    func updateTabBarVisibility() {
        guard let tabBarController = nearestTabBarController() else { return }
        if tabBarControllerToRestore !== tabBarController {
            tabBarControllerToRestore = tabBarController
            previousHiddenState = tabBarController.tabBar.isHidden
        }
        tabBarController.tabBar.isHidden = true
    }

    private func restoreTabBar() {
        guard let tabBarControllerToRestore else { return }
        tabBarControllerToRestore.tabBar.isHidden = previousHiddenState
        self.tabBarControllerToRestore = nil
    }

    private func nearestTabBarController() -> UITabBarController? {
        var current: UIViewController? = self
        while let viewController = current {
            if let tabBarController = viewController as? UITabBarController {
                return tabBarController
            }
            current = viewController.parent
        }

        guard let root = view.window?.rootViewController else { return nil }
        return findTabBarController(in: root)
    }

    private func findTabBarController(in viewController: UIViewController) -> UITabBarController? {
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }
        for child in viewController.children {
            if let result = findTabBarController(in: child) {
                return result
            }
        }
        return nil
    }
}

private struct AccountIconOption: Identifiable, Hashable {
    let symbolName: String
    let title: String
    let group: String

    var id: String { symbolName }
}

private enum AccountIconCatalog {
    static let all: [AccountIconOption] = [
        AccountIconOption(symbolName: "building.columns.fill", title: "Banca", group: "Banche"),
        AccountIconOption(symbolName: "building.columns", title: "Istituto", group: "Banche"),
        AccountIconOption(symbolName: "banknote.fill", title: "Contanti", group: "Contanti"),
        AccountIconOption(symbolName: "eurosign.circle.fill", title: "Euro", group: "Contanti"),
        AccountIconOption(symbolName: "dollarsign.circle.fill", title: "Dollaro", group: "Contanti"),
        AccountIconOption(symbolName: "creditcard.fill", title: "Carta", group: "Carte"),
        AccountIconOption(symbolName: "wallet.bifold.fill", title: "Portafoglio", group: "Portafoglio"),
        AccountIconOption(symbolName: "briefcase.fill", title: "Lavoro", group: "Attività"),
        AccountIconOption(symbolName: "chart.line.uptrend.xyaxis", title: "Risparmi", group: "Risparmi"),
        AccountIconOption(symbolName: "house.fill", title: "Casa", group: "Altro"),
        AccountIconOption(symbolName: "airplane", title: "Viaggio", group: "Altro"),
        AccountIconOption(symbolName: "ellipsis.circle.fill", title: "Altro", group: "Altro")
    ].filter { UIImage(systemName: $0.symbolName) != nil }
}

private struct AccountIconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(AccountIconCatalog.all) { option in
                    Button {
                        selection = option.symbolName
                        dismiss()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: option.symbolName)
                                .font(.system(size: 23, weight: .semibold))
                                .frame(width: 50, height: 50)
                                .foregroundStyle(Color.PrimaryText)
                                .background(Color.AppSecondarySurface, in: Circle())
                                .overlay {
                                    Circle()
                                        .stroke(selection == option.symbolName ? Color.accentColor : .clear, lineWidth: 2)
                                }
                            Text(option.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 60, minHeight: 70)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityValue(selection == option.symbolName ? "Selezionata" : "")
                }
            }
            .padding(20)
        }
        .background(Color.AppPageBackground)
        .navigationTitle("Icona")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annulla") { dismiss() }
            }
        }
    }
}

struct AccountEditorView: View {
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]) private var history: FetchedResults<Transaction>
    let account: Account?
    @State private var name: String
    @State private var type: AccountType
    @State private var openingBalanceText: String
    @State private var currencyCode: String
    @State private var iconName: String
    @State private var colour: String
    @State private var isArchived: Bool
    @State private var errorMessage: String?
    @State private var showingIconPicker = false
    @FocusState private var focusedField: EditorField?

    private enum EditorField {
        case name
        case openingBalance
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedOpeningBalance: Double? {
        Self.parseDecimal(openingBalanceText)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty &&
        parsedOpeningBalance != nil &&
        Currency.currencyCodes.contains(currencyCode) &&
        AccountIconCatalog.all.contains(where: { $0.symbolName == iconName }) &&
        isValidColour
    }

    private var selectedColor: Color { Color(hex: colour) }

    private var isValidColour: Bool {
        let value = colour.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6 || value.count == 8 else { return false }
        return value.allSatisfy { $0.isHexDigit }
    }

    private var previewBalance: Double { parsedOpeningBalance ?? 0 }

    init(account: Account?) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.wrappedType ?? .bank)
        _openingBalanceText = State(initialValue: Self.displayDecimal(account?.openingBalance ?? 0))
        _currencyCode = State(initialValue: account?.currencyCode ?? UserDefaults(suiteName: "group.com.saied.sa7tot")?.string(forKey: "currency") ?? Locale.current.currencyCode ?? "EUR")
        let storedIcon = account?.iconName ?? "building.columns.fill"
        _iconName = State(initialValue: AccountIconCatalog.all.contains(where: { $0.symbolName == storedIcon }) ? storedIcon : "building.columns.fill")
        _colour = State(initialValue: account?.wrappedColour ?? "#5E7CE2")
        _isArchived = State(initialValue: account?.isArchived ?? false)
        _errorMessage = State(initialValue: nil)
    }

    var body: some View {
        Form {
            Section("Informazioni") {
                TextField("Nome del conto", text: $name)
                    .focused($focusedField, equals: .name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focusedField = .openingBalance }
                Picker("Tipo di conto", selection: $type) {
                    ForEach(AccountType.allCases) { item in Text(item.italianName).tag(item) }
                }
            }

            Section("Saldo") {
                HStack {
                    Text("Saldo iniziale")
                    Spacer()
                    TextField("0,00", text: $openingBalanceText)
                        .focused($focusedField, equals: .openingBalance)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 110)
                        .accessibilityLabel("Saldo iniziale")
                }
                Picker("Valuta", selection: $currencyCode) {
                    ForEach(Currency.allCurrencies, id: \.code) { currency in
                        Text("\(currency.code) — \(currency.name)").tag(currency.code)
                    }
                }
            }

            Section("Aspetto") {
                Button {
                    showingIconPicker = true
                } label: {
                    HStack {
                        Text("Icona")
                        Spacer()
                        Image(systemName: iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.PrimaryText)
                            .frame(width: 44, height: 44)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Icona")
                .accessibilityValue(AccountIconCatalog.all.first(where: { $0.symbolName == iconName })?.title ?? "Seleziona icona")

                ColorPicker("Colore", selection: Binding(
                    get: { Color(hex: colour) },
                    set: { colour = $0.toHex() ?? colour }
                ), supportsOpacity: false)
                .accessibilityLabel("Colore")

                if account != nil { Toggle("Archiviato", isOn: $isArchived) }
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: iconName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.PrimaryText)
                        .frame(width: 44, height: 44)
                        .background(selectedColor, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(trimmedName.isEmpty ? "Nome del conto" : trimmedName)
                            .font(.headline)
                        Text(previewBalance, format: .currency(code: currencyCode))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Anteprima conto")
            } header: {
                Text("Anteprima")
            }

            if let account, !account.canDelete {
                Section { Text("Questo conto contiene movimenti o modelli e non può essere eliminato. Puoi archiviarlo.").font(.footnote).foregroundColor(.secondary) }
            }
            if let account {
                let accountHistory = history.filter { $0.account == account || $0.destinationAccount == account }
                Section("Movimenti") {
                    if accountHistory.isEmpty {
                        Text("Nessun movimento")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(accountHistory) { transaction in
                            HStack {
                                Image(systemName: transaction.isTransfer ? "arrow.left.arrow.right" : (transaction.income ? "plus" : "minus"))
                                VStack(alignment: .leading) {
                                    Text(transaction.isTransfer ? "Trasferimento" : transaction.wrappedNote)
                                    if transaction.isTransfer {
                                        Text(transaction.account == account ? "A \(transaction.destinationAccount?.name ?? "Conto")" : "Da \(transaction.account?.name ?? "Conto")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Text(transaction.amount, format: .currency(code: account.currencyCode ?? "EUR"))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(account == nil ? "Nuovo conto" : "Modifica conto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annulla") { dismiss() }
                    .opacity(account == nil ? 1 : 0)
                    .disabled(account != nil)
                    .accessibilityHidden(account != nil)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    if let account, account.currencyCode != currencyCode, !account.canChangeCurrency {
                        errorMessage = "La valuta non può essere cambiata dopo la registrazione di movimenti o modelli."
                        return
                    }
                    let target = account ?? Account(context: moc)
                    target.id = target.id ?? UUID()
                    target.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Conto principale" : name
                    target.typeRawValue = type.rawValue
                    guard let openingBalance = parsedOpeningBalance else {
                        errorMessage = "Inserisci un saldo iniziale valido."
                        return
                    }
                    target.openingBalance = openingBalance
                    target.currencyCode = currencyCode
                    target.iconName = iconName
                    target.colour = colour
                    target.isArchived = isArchived
                    target.createdAt = target.createdAt ?? Date()
                    if account == nil { target.order = Int32((try? moc.count(for: Account.fetchRequest())) ?? 1) }
                    do {
                        try dataController.saveAccountChanges()
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .disabled(!isValid)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fine") {
                    focusedField = nil
                    UIApplication.shared.endEditing()
                }
                .accessibilityLabel("Fine modifica")
            }
        }
        .sheet(isPresented: $showingIconPicker) {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    AccountIconPickerView(selection: $iconName)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            } else {
                NavigationView {
                    AccountIconPickerView(selection: $iconName)
                }
            }
        }
        .alert("Errore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Impossibile salvare le modifiche.")
        }
    }

    private static func displayDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "0,00"
    }

    private static func parseDecimal(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var normalized = trimmed.replacingOccurrences(of: " ", with: "")
        if normalized.contains(",") {
            normalized = normalized.replacingOccurrences(of: ".", with: "")
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        } else if Locale.current.decimalSeparator == "," {
            let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count > 2 || (parts.count == 2 && parts[1].count > 2) {
                normalized = normalized.replacingOccurrences(of: ".", with: "")
            }
        }

        guard normalized.range(of: #"^[+-]?\d+(\.\d+)?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return NSDecimalNumber(decimal: decimal).doubleValue
    }
}

struct WalletAutomationView: View {
    @EnvironmentObject private var dataController: DataController
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "order", ascending: true)]) private var accounts: FetchedResults<Account>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]) private var reviewTransactions: FetchedResults<Transaction>
    @State private var fallbackID = ""
    @State private var errorMessage: String?
    @State private var testMessage: String?
    @State private var showTestConfirmation = false

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }
    private var reviewCount: Int { reviewTransactions.filter { $0.wrappedReviewStatus == .needsReview }.count }
    private var mappedAccounts: [Transaction] { [] }

    var body: some View {
        Form {
            Section("Automazione Wallet") {
                Text("Sa7tot non legge le notifiche di altre app. Collega manualmente un’automazione Transazione di Comandi Rapidi all’azione “Registra spesa da Wallet”.")
                    .font(.footnote)
                NavigationLink("Guida di configurazione") { WalletSetupGuideView() }
                NavigationLink("Da controllare (\(reviewCount))") { WalletReviewView() }
            }

            Section("Conto fallback") {
                Picker("Usa se Wallet non invia l’etichetta", selection: $fallbackID) {
                    Text("Nessun fallback").tag("")
                    ForEach(activeAccounts) { account in
                        Text(account.name ?? "Conto").tag(account.id?.uuidString ?? "")
                    }
                }
                .onChange(of: fallbackID) { value in
                    UserDefaults(suiteName: "group.com.saied.sa7tot")?.set(value.isEmpty ? nil : value, forKey: "walletFallbackAccountID")
                }
            }

            Section("Etichette Wallet") {
                ForEach(accounts) { account in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(account.name ?? "Conto")
                            .font(.headline)
                        TextField("Es. Revolut, PostePay, Intesa Sanpaolo", text: Binding(
                            get: { account.walletLabel ?? "" },
                            set: { account.walletLabel = $0 }
                        ), onCommit: { saveMapping(account) })
                        .disabled(account.isArchived)
                        if account.isArchived {
                            Text("Conto archiviato: non riceverà nuove spese Wallet.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Prova automazione") {
                Button("Prova automazione") { showTestConfirmation = true }
                    .disabled(activeAccounts.first(where: { $0.normalizedWalletLabel != nil }) == nil)
                Text("La prova usa gli stessi parser, mapping, categorizzazione, deduplica e notifiche dell’azione Shortcuts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Automazione Wallet")
        .onAppear {
            fallbackID = UserDefaults(suiteName: "group.com.saied.sa7tot")?.string(forKey: "walletFallbackAccountID") ?? ""
            Task { await WalletNotificationService.requestPermission() }
        }
        .alert("Confermi la prova?", isPresented: $showTestConfirmation) {
            Button("Registra prova", role: .destructive) { runTest() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Verrà registrata una spesa locale di prova da Esselunga per 12,50 €. Puoi eliminarla dall’app.")
        }
        .alert("Automazione Wallet", isPresented: Binding(get: { errorMessage != nil || testMessage != nil }, set: { if !$0 { errorMessage = nil; testMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil; testMessage = nil }
        } message: {
            Text(errorMessage ?? testMessage ?? "")
        }
    }

    private func saveMapping(_ account: Account) {
        do {
            try WalletAccountResolver.validateUnique(label: account.walletLabel, account: account, accounts: Array(accounts))
            try dataController.saveAccountChanges()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Etichetta Wallet non valida."
        }
    }

    private func runTest() {
        guard let account = activeAccounts.first(where: { $0.normalizedWalletLabel != nil }), let label = account.walletLabel else {
            errorMessage = "Collega prima un’etichetta Wallet a un conto attivo."
            return
        }
        do {
            _ = try dataController.newWalletExpense(amountRaw: "12,50", merchant: "Esselunga", date: Date(), walletAccountLabel: label, note: "Prova automazione Wallet", externalReference: "sa7tot-wallet-test-\(Int(Date().timeIntervalSince1970))")
            testMessage = "Spesa di prova registrata."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Impossibile eseguire la prova."
        }
    }
}

struct WalletSetupGuideView: View {
    var body: some View {
        List {
            Section("Configurazione manuale") {
                Text("1. Apri Comandi Rapidi.")
                Text("2. Vai su Automazione e tocca Nuova automazione.")
                Text("3. Scegli Transazione e seleziona la carta.")
                Text("4. Seleziona Esegui immediatamente.")
                Text("5. Aggiungi l’azione “Registra spesa da Wallet” di Sa7tot.")
                Text("6. Collega Importo, Esercente, Data e Carta ai parametri dell’azione.")
                Text("7. Salva l’automazione.")
            }
            Section {
                Text("Le variabili disponibili possono cambiare in base alla versione di iOS, alla carta e alla banca. Sa7tot non legge notifiche bancarie e non si collega direttamente al conto.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Guida Wallet")
    }
}

struct WalletReviewView: View {
    @EnvironmentObject private var dataController: DataController
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
        predicate: NSPredicate(format: "reviewStatusRawValue == %@", TransactionReviewStatus.needsReview.rawValue)
    ) private var transactions: FetchedResults<Transaction>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "order", ascending: true)], predicate: NSPredicate(format: "income = NO")) private var categories: FetchedResults<Category>

    var body: some View {
        List {
            if transactions.isEmpty {
                Text("Nessuna spesa da controllare.").foregroundColor(.secondary)
            }
            ForEach(transactions) { transaction in
                VStack(alignment: .leading, spacing: 8) {
                    Text(transaction.amount, format: .currency(code: transaction.account?.currencyCode ?? "EUR"))
                        .font(.headline)
                    TextField("Esercente", text: Binding(get: { transaction.merchant ?? "" }, set: { transaction.merchant = $0 }))
                    Text(transaction.account?.name ?? "Conto non disponibile")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Menu("Categoria: \(transaction.category?.wrappedName ?? "Da scegliere")") {
                        ForEach(categories) { category in
                            Button(category.wrappedName) { transaction.category = category }
                        }
                    }
                    Button("Conferma movimento") {
                        transaction.normalizedMerchant = WalletTextNormalizer.normalize(transaction.merchant)
                        transaction.reviewStatusRawValue = TransactionReviewStatus.confirmed.rawValue
                        try? dataController.saveAccountChanges()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Da controllare")
    }
}
