import CoreData
import SwiftUI

struct AccountMenuView: View {
    let accounts: [Account]
    @Binding var account: Account?

    var body: some View {
        Menu {
            ForEach(accounts.filter { !$0.isArchived }) { item in
                Button { account = item } label: {
                    Label(item.name ?? "Conto", systemImage: item.iconName ?? "building.columns.fill")
                }
            }
        } label: {
            Label(account?.name ?? "Conto", systemImage: account?.iconName ?? "building.columns.fill")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundColor(Color.PrimaryText)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 11.5, style: .continuous))
        }
        .accessibilityLabel("Conto: \(account?.name ?? "Conto principale")")
    }
}

struct AccountListView: View {
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var dataController: DataController
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "order", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)])
    private var accounts: FetchedResults<Account>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)])
    private var transactions: FetchedResults<Transaction>
    @State private var showingEditor = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(accounts) { account in
                NavigationLink {
                    AccountEditorView(account: account)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: account.iconName ?? "building.columns.fill")
                            .foregroundColor(Color(hex: account.wrappedColour))
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
        .navigationTitle("Conti")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingEditor = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationView { AccountEditorView(account: nil) }
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

struct AccountEditorView: View {
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]) private var history: FetchedResults<Transaction>
    let account: Account?
    @State private var name: String
    @State private var type: AccountType
    @State private var openingBalance: Double
    @State private var currencyCode: String
    @State private var iconName: String
    @State private var colour: String
    @State private var isArchived: Bool
    @State private var errorMessage: String?

    init(account: Account?) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.wrappedType ?? .bank)
        _openingBalance = State(initialValue: account?.openingBalance ?? 0)
        _currencyCode = State(initialValue: account?.currencyCode ?? UserDefaults(suiteName: "group.com.saied.sa7tot")?.string(forKey: "currency") ?? Locale.current.currencyCode ?? "EUR")
        _iconName = State(initialValue: account?.iconName ?? "building.columns.fill")
        _colour = State(initialValue: account?.wrappedColour ?? "#5E7CE2")
        _isArchived = State(initialValue: account?.isArchived ?? false)
        _errorMessage = State(initialValue: nil)
    }

    var body: some View {
        Form {
            Section("Dettagli") {
                TextField("Nome", text: $name)
                Picker("Tipo", selection: $type) {
                    ForEach(AccountType.allCases) { item in Text(item.italianName).tag(item) }
                }
                TextField("Saldo iniziale", value: $openingBalance, format: .number)
                TextField("Codice valuta", text: $currencyCode)
                TextField("Icona SF Symbol", text: $iconName)
                TextField("Colore esadecimale", text: $colour)
                if account != nil { Toggle("Archiviato", isOn: $isArchived) }
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
        .toolbar {
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
            }
        }
        .alert("Errore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Impossibile salvare le modifiche.")
        }
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
