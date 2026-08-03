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
