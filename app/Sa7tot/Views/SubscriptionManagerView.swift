import SwiftUI

struct SubscriptionManagerView: View {
    @EnvironmentObject private var remoteStore: FinancialRemoteStore
    @State private var selectedRemoteSubscription: RemoteSubscriptionDTO?
    @State private var showCancelConfirmation = false
    @State private var remoteActionError: String?

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
    private var showCents = true

    var body: some View {
        Group {
            if #available(iOS 26.0, *), remoteStore.isRemoteOnly {
                remoteBody
            } else {
                RemoteConfigurationUnavailableView()
            }
        }
        .background(Color.AppPageBackground)
        .navigationTitle("Abbonamenti")
        .navigationBarTitleDisplayMode(.large)
        .task {
            do {
                try await remoteStore.loadSubscriptions()
            } catch is CancellationError {
            } catch {
            }
        }
        .sheet(item: $selectedRemoteSubscription) { subscription in
            if #available(iOS 26.0, *) {
                RemoteSubscriptionDetailView(subscription: subscription)
            } else {
                EmptyView()
            }
        }
        .alert("Impossibile annullare l'abbonamento", isPresented: Binding(
            get: { remoteActionError != nil },
            set: { if !$0 { remoteActionError = nil } }
        )) {
            Button("OK", role: .cancel) { remoteActionError = nil }
        } message: {
            Text(remoteActionError ?? "Riprova.")
        }
        .alert("Annullare l'abbonamento?", isPresented: $showCancelConfirmation) {
            Button("Annulla abbonamento", role: .destructive) {
                guard let subscription = selectedRemoteSubscription else { return }
                Task {
                    do { try await remoteStore.cancelSubscription(subscription.id) }
                    catch { remoteActionError = "Impossibile annullare l'abbonamento. Riprova." }
                }
            }
            Button("Indietro", role: .cancel) {}
        } message: {
            Text("L'abbonamento non verrà più mostrato nell'elenco principale.")
        }
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private var remoteBody: some View {
        let visible = remoteStore.subscriptions.filter { $0.status == .active || $0.status == .paused }
        if visible.isEmpty {
            emptyState
        } else {
            List(visible, id: \.id) { subscription in
                remoteSubscriptionRow(subscription)
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                "Nessun abbonamento",
                systemImage: "repeat.circle",
                description: Text("Aggiungi un abbonamento dal pulsante +.")
            )
        } else {
            VStack(spacing: 10) {
                Image(systemName: "repeat.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Nessun abbonamento")
                    .font(.headline)
                Text("Aggiungi un abbonamento dal pulsante +.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
        }
    }

    private func remoteSubscriptionRow(_ subscription: RemoteSubscriptionDTO) -> some View {
        Button {
            selectedRemoteSubscription = subscription
        } label: {
            HStack(spacing: 12) {
                SubscriptionLogoView(service: SubscriptionServiceCatalog.service(forID: subscription.serviceID), size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(subscription.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if subscription.status == .paused {
                            Text("In pausa")
                        } else {
                            Text(formattedDate(subscription.nextBillingDate))
                        }
                        Text("·").foregroundStyle(.tertiary)
                        Text(remoteCadenceTitle(subscription.cadence))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(formattedAmount(subscription.amount))
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Modifica") { selectedRemoteSubscription = subscription }
            if subscription.status == .paused {
                Button("Riprendi") { performRemoteAction { try await remoteStore.resumeSubscription(subscription.id) } }
            } else {
                Button("Metti in pausa") { performRemoteAction { try await remoteStore.pauseSubscription(subscription.id) } }
            }
            Button("Annulla abbonamento", role: .destructive) {
                selectedRemoteSubscription = subscription
                showCancelConfirmation = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subscription.displayName)
        .accessibilityValue("\(remoteCadenceTitle(subscription.cadence)), \(subscription.status == .paused ? "In pausa" : "Attivo")")
    }

    private func performRemoteAction(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action() }
            catch { remoteActionError = "Impossibile aggiornare l'abbonamento. Riprova." }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func formattedAmount(_ amount: RemoteMoney) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = amount.currencyCode
        formatter.minimumFractionDigits = showCents ? amount.exponent : 0
        formatter.maximumFractionDigits = showCents ? amount.exponent : 0
        return formatter.string(from: NSNumber(value: Double(amount.minorUnits) / pow(10, Double(amount.exponent)))) ?? "0"
    }

    private func formattedDate(_ date: RemoteDateOnly) -> String {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = date.year
        components.month = date.month
        components.day = date.day
        let value = components.calendar?.date(from: components) ?? .now
        return formattedDate(value)
    }

    private func remoteCadenceTitle(_ cadence: RemoteSubscriptionCadence) -> String {
        switch cadence {
        case .weekly: return "Settimanale"
        case .monthly: return "Mensile"
        case .yearly: return "Annuale"
        }
    }

}

@available(iOS 26.0, *)
private struct RemoteSubscriptionDetailView: View {
    let subscription: RemoteSubscriptionDTO
    @EnvironmentObject private var store: FinancialRemoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        SubscriptionLogoView(service: SubscriptionServiceCatalog.service(forID: subscription.serviceID), size: 52)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(subscription.displayName).font(.title3.weight(.semibold))
                            Text(subscription.status == .paused ? "In pausa" : "Attivo")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                Section {
                    detailRow("Importo", detailAmount)
                    detailRow("Frequenza", cadenceTitle)
                    detailRow("Prossimo pagamento", subscription.nextBillingDate.isoString)
                    if let account = store.accounts.first(where: { $0.id == subscription.accountID }) {
                        detailRow("Conto", account.name)
                    }
                }
            }
            .navigationTitle("Abbonamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Modifica") { showEditor = true } }
            }
            .sheet(isPresented: $showEditor) {
                RemoteSubscriptionEditorView(subscription: subscription)
            }
        }
    }

    private var cadenceTitle: String {
        switch subscription.cadence {
        case .weekly: return "Settimanale"
        case .monthly: return "Mensile"
        case .yearly: return "Annuale"
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private var detailAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = subscription.currencyCode
        formatter.minimumFractionDigits = subscription.currencyExponent
        formatter.maximumFractionDigits = subscription.currencyExponent
        return formatter.string(from: NSNumber(value: Double(subscription.amountMinor) / pow(10, Double(subscription.currencyExponent)))) ?? "0"
    }
}
