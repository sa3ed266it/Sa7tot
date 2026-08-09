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
        .navigationTitle(AppLocalization.key("subscription.title"))
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
        .alert(AppLocalization.key("subscription.cancelErrorTitle"), isPresented: Binding(
            get: { remoteActionError != nil },
            set: { if !$0 { remoteActionError = nil } }
        )) {
            Button(AppLocalization.key("action.ok"), role: .cancel) { remoteActionError = nil }
        } message: {
            Text(verbatim: remoteActionError ?? AppLocalization.string("action.retry"))
        }
        .alert(AppLocalization.key("subscription.cancelTitle"), isPresented: $showCancelConfirmation) {
            Button(AppLocalization.key("subscription.cancel"), role: .destructive) {
                guard let subscription = selectedRemoteSubscription else { return }
                Task {
                    do { try await remoteStore.cancelSubscription(subscription.id) }
                    catch { remoteActionError = AppLocalization.string("subscription.cancelError") }
                }
            }
            Button(AppLocalization.key("action.cancel"), role: .cancel) {}
        } message: {
            Text(AppLocalization.key("subscription.cancelMessage"))
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
                AppLocalization.key("subscription.empty"),
                systemImage: "repeat.circle",
                description: Text(AppLocalization.key("subscription.emptyDescription"))
            )
        } else {
            VStack(spacing: 10) {
                Image(systemName: "repeat.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(AppLocalization.key("subscription.empty"))
                    .font(.headline)
                Text(AppLocalization.key("subscription.emptyDescription"))
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
                            Text(AppLocalization.key("subscription.paused"))
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
            Button(AppLocalization.key("action.edit")) { selectedRemoteSubscription = subscription }
            if subscription.status == .paused {
                Button(AppLocalization.key("action.resume")) { performRemoteAction { try await remoteStore.resumeSubscription(subscription.id) } }
            } else {
                Button(AppLocalization.key("action.pause")) { performRemoteAction { try await remoteStore.pauseSubscription(subscription.id) } }
            }
            Button(AppLocalization.key("subscription.cancel"), role: .destructive) {
                selectedRemoteSubscription = subscription
                showCancelConfirmation = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subscription.displayName)
        .accessibilityValue(AppLocalization.format("accessibility.subscription", remoteCadenceTitle(subscription.cadence), AppLocalization.string(subscription.status == .paused ? "subscription.paused" : "subscription.active")))
    }

    private func performRemoteAction(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action() }
            catch { remoteActionError = AppLocalization.string("subscription.updateError") }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func formattedAmount(_ amount: RemoteMoney) -> String {
        return FinancialFormatting.currency(minorUnits: amount.minorUnits, currencyCode: amount.currencyCode, exponent: amount.exponent, showCents: showCents)
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
        case .weekly: return AppLocalization.string("subscription.weekly")
        case .monthly: return AppLocalization.string("subscription.monthly")
        case .yearly: return AppLocalization.string("subscription.yearly")
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
                            Text(AppLocalization.key(subscription.status == .paused ? "subscription.paused" : "subscription.active"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                Section {
                    detailRow(AppLocalization.string("common.amount"), detailAmount)
                    detailRow(AppLocalization.string("common.frequency"), cadenceTitle)
                    detailRow(AppLocalization.string("subscription.nextPayment"), subscription.nextBillingDate.isoString)
                    if let account = store.accounts.first(where: { $0.id == subscription.accountID }) {
                        detailRow(AppLocalization.string("common.account"), account.name)
                    }
                }
            }
            .navigationTitle(AppLocalization.key("subscription.detail"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.key("action.close")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(AppLocalization.key("action.edit")) { showEditor = true } }
            }
            .sheet(isPresented: $showEditor) {
                RemoteSubscriptionEditorView(subscription: subscription)
            }
        }
    }

    private var cadenceTitle: String {
        switch subscription.cadence {
        case .weekly: return AppLocalization.string("subscription.weekly")
        case .monthly: return AppLocalization.string("subscription.monthly")
        case .yearly: return AppLocalization.string("subscription.yearly")
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value).multilineTextAlignment(.trailing)
        }
    }

    private var detailAmount: String {
        return FinancialFormatting.currency(minorUnits: subscription.amountMinor, currencyCode: subscription.currencyCode, exponent: subscription.currencyExponent)
    }
}
