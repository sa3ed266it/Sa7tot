import SwiftUI
import UIKit

private enum RemoteClashDisplayFont {
    static func font(size: CGFloat) -> Font {
        ClashDisplayFont.font(size: size)
    }
}

private let remotePrivacyBlurRadius: CGFloat = 16
private let remoteSubheaderBlurRadius: CGFloat = 6
private let remotePrivacyTransition = Animation.easeInOut(duration: 0.22)

private func remoteAmount(_ minor: Int64, currencyCode: String, exponent: Int, showCents: Bool = true) -> String {
    let number = NSDecimalNumber(mantissa: UInt64(abs(minor)), exponent: Int16(-exponent), isNegative: minor < 0)
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currencyCode
    formatter.maximumFractionDigits = showCents ? exponent : 0
    formatter.minimumFractionDigits = showCents ? exponent : 0
    return formatter.string(from: number) ?? "(minor)"
}

private func remoteAmountDigits(_ minor: Int64, currencyCode: String, exponent: Int, showCents: Bool = true) -> String {
    let number = NSDecimalNumber(mantissa: UInt64(abs(minor)), exponent: Int16(-exponent), isNegative: false)
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale.current
    formatter.maximumFractionDigits = showCents ? exponent : 0
    formatter.minimumFractionDigits = showCents ? exponent : 0
    return formatter.string(from: number) ?? "0"
}

private func remoteSignedAmount(_ minor: Int64, currencyCode: String, exponent: Int, showCents: Bool = true) -> String {
    let absolute = remoteAmount(abs(minor), currencyCode: currencyCode, exponent: exponent, showCents: showCents)
    return minor > 0 ? "+\(absolute)" : minor < 0 ? "-\(absolute)" : absolute
}

private func remoteDate(_ value: RemoteDateOnly) -> Date? {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = .current
    components.year = value.year
    components.month = value.month
    components.day = value.day
    return components.calendar?.date(from: components)
}

private func remoteDateLabel(_ value: RemoteDateOnly) -> String {
    guard let date = remoteDate(value) else { return value.isoString }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    formatter.locale = .current
    return formatter.string(from: date)
}

private func remoteTimeLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    formatter.locale = .current
    return formatter.string(from: date)
}

@available(iOS 26.0, *)
struct RemoteFinancialHomeView: View {
    @EnvironmentObject private var store: FinancialRemoteStore

    @State private var currentTab = Sa7totMainTabConfiguration.movements
    @State private var route: RemoteFinancialRoute?
    @StateObject private var settingsNavigationRouter = NativeSettingsNavigationRouter()

    let topEdge: CGFloat
    let bottomEdge: CGFloat

    var body: some View {
        NativeSearchTabView(
            selection: $currentTab,
            logView: hosted(RemoteMovimentiView(
                onAdd: { route = store.activeAccounts.isEmpty ? .account : .transaction(nil) },
                onTransfer: { route = .transfer }
            )),
            subscriptionView: hosted(SubscriptionManagerView()),
            settingsView: hosted(
                SettingsView(
                    usesNativeNavigation: true,
                    nativeNavigationRouter: settingsNavigationRouter
                )
            ),
            settingsNavigationRouter: settingsNavigationRouter,
            onAdd: { route = store.activeAccounts.isEmpty ? .account : .transaction(nil) }
        )
        .sheet(item: $route) { route in
            switch route {
            case let .transaction(transaction):
                RemoteTransactionEditorView(transaction: transaction, initialAccountID: store.selectedAccountID)
                    .environmentObject(store)
            case .transfer:
                RemoteTransferEditorView()
                    .environmentObject(store)
            case .account:
                RemoteAccountEditorView(account: nil)
                    .environmentObject(store)
            }
        }
        .task {
            await store.bootstrapIfNeeded()
        }
    }

    private func hosted<V: View>(_ view: V) -> AnyView {
        AnyView(
            view
                .environmentObject(store)
        )
    }
}

struct RemoteConfigurationUnavailableView: View {
    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label("Configurazione non disponibile", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Controlla la configurazione del servizio e riprova.")
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                Text("Configurazione non disponibile")
                    .font(.headline)
                Text("Controlla la configurazione del servizio e riprova.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

private enum RemoteFinancialRoute: Identifiable {
    case transaction(RemoteTransactionDTO?)
    case transfer
    case account

    var id: String {
        switch self {
        case let .transaction(transaction): return "transaction-\(transaction?.id.uuidString ?? "new")"
        case .transfer: return "transfer"
        case .account: return "account"
        }
    }
}

@available(iOS 26.0, *)
struct RemoteMovimentiView: View {
    @EnvironmentObject private var store: FinancialRemoteStore
    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) private var showCents = true
    @AppStorage("hideBalances", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) private var hideBalances = false

    let onAdd: () -> Void
    let onTransfer: () -> Void

    @State private var detail: RemoteTransactionDTO?
    @State private var editing: RemoteTransactionDTO?
    @State private var deleteCandidate: RemoteTransactionDTO?
    @State private var isDeleteAlertPresented = false
    @State private var balanceCollapseProgress: CGFloat = 0
    @State private var expandedBalanceHeaderHeight: CGFloat = 175
    @State private var displayedContentIsEmpty = false

    private let compactBalanceHeaderHeight: CGFloat = 54

    private var balanceHandoff: CGFloat {
        min(max((balanceCollapseProgress - 0.50) / 0.28, 0), 1)
    }

    private var selectedBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedAccountID },
            set: { if let value = $0 { store.selectAccount(value) } }
        )
    }

    var body: some View {
        Group {
            if store.isLoading && store.accounts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.activeAccounts.isEmpty {
                ContentUnavailableView {
                    Label("Nessun conto", systemImage: "building.columns")
                } description: {
                    Text("Aggiungi un conto per iniziare a registrare i movimenti.")
                } actions: {
                    Button("Aggiungi conto", action: onAdd)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                movementContent
            }
        }
        .background(Color.AppPageBackground)
        .background {
            RemoteNativeFilterMenuBridge(
                filter: $store.filter,
                hideBalances: $hideBalances,
                selectedAccountID: store.selectedAccountID,
                onFilter: { store.setFilter($0) },
                onTransfer: onTransfer
            )
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if store.filter == .all, let account = store.selectedAccount {
                    RemoteCompactBalanceToolbarTitle(
                        accountName: account.name,
                        showCents: showCents,
                        currencySymbol: remoteCurrencySymbol(for: account.currencyCode),
                        netTotal: (abs(store.selectedSnapshot?.balanceMinor ?? 0), (store.selectedSnapshot?.balanceMinor ?? 0) >= 0),
                        currencyCode: account.currencyCode,
                        currencyExponent: account.currencyExponent,
                        hideBalances: hideBalances
                    )
                    .opacity(balanceHandoff)
                    .offset(y: 4 * (1 - balanceHandoff))
                    .allowsHitTesting(false)
                    .accessibilityHidden(balanceHandoff < 0.5)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { transaction in
            RemoteTransactionDetailView(transaction: transaction, selectedAccountID: store.selectedAccountID)
                .environmentObject(store)
        }
        .sheet(item: $editing) { transaction in
            RemoteTransactionEditorView(transaction: transaction, initialAccountID: store.selectedAccountID)
                .environmentObject(store)
        }
        .alert("Eliminare il movimento?", isPresented: $isDeleteAlertPresented, presenting: deleteCandidate) { transaction in
            Button("Elimina", role: .destructive) {
                Task {
                    try? await store.deleteTransaction(transaction.id)
                }
            }
            Button("Annulla", role: .cancel) {}
        } message: { _ in
            Text("Questa azione non può essere annullata.")
        }
        .alert("Errore", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("Riprova") { Task { await store.refresh() } }
            Button("Annulla", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Impossibile caricare i movimenti.")
        }
        .alert("Funzione in arrivo", isPresented: Binding(get: { store.deferredFeatureMessage != nil }, set: { if !$0 { store.deferredFeatureMessage = nil } })) {
            Button("OK", role: .cancel) { store.deferredFeatureMessage = nil }
        } message: {
            Text(store.deferredFeatureMessage ?? "Questa funzione non è ancora disponibile.")
        }
    }

    private var movementContent: some View {
        VStack(spacing: 0) {
            if store.filter != .all && store.filter != .recurring && store.filter != .upcoming {
                remoteFilterHeader
            }

            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            Color.clear.frame(height: 0).id("remote-movements-top")

                            if store.filter == .all {
                                RemoteAccountPager(
                                    selectedAccountID: selectedBinding,
                                    hideBalances: hideBalances,
                                    showCents: showCents,
                                    collapseProgress: balanceCollapseProgress,
                                    handoff: balanceHandoff
                                )
                                .opacity(1 - balanceHandoff)
                                .overlay(alignment: .top) {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: RemoteBalanceHeaderMetricsKey.self,
                                            value: RemoteBalanceHeaderMetrics(minY: proxy.frame(in: .named("RemoteHomeScroll")).minY, height: proxy.size.height)
                                        )
                                    }
                                    .allowsHitTesting(false)
                                }
                            }

                            remoteMovementList

                            if store.filter == .all {
                                Color.clear.frame(height: 180).allowsHitTesting(false)
                            }
                        }
                    }
                    .coordinateSpace(name: "RemoteHomeScroll")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(RemoteScrollProgressModifier { offset in
                        let collapseDistance = max(1, expandedBalanceHeaderHeight - compactBalanceHeaderHeight)
                        balanceCollapseProgress = min(max(offset / collapseDistance, 0), 1)
                    })
                    .onChange(of: store.selectedAccountID) { _ in
                        proxy.scrollTo("remote-movements-top", anchor: .top)
                        balanceCollapseProgress = 0
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPreferenceChange(RemoteBalanceHeaderMetricsKey.self) { metrics in
                expandedBalanceHeaderHeight = metrics.height
                let collapseDistance = max(1, metrics.height - compactBalanceHeaderHeight)
                balanceCollapseProgress = min(max(-metrics.minY / collapseDistance, 0), 1)
            }
        }
        .refreshable { await store.refresh() }
    }

    @ViewBuilder
    private var remoteMovementList: some View {
        if store.filter == .upcoming {
            remoteUpcomingList
        } else if store.days.isEmpty && !store.isLoading {
            NoResultsView(fullscreen: true)
        } else {
            remoteHistoryList
        }
    }

    @ViewBuilder
    private var remoteHistoryList: some View {
        ForEach(store.days, id: \.day) { day in
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    HStack {
                        Text(remoteDateLabel(day.day).uppercased())
                        Spacer()
                        Text(remoteSignedAmount(day.subtotalMinor, currencyCode: store.selectedCurrencyCode, exponent: store.selectedCurrencyExponent, showCents: showCents))
                            .monospacedDigit()
                            .layoutPriority(1)
                    }
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.SubtitleText)

                    Line().stroke(Color.Outline, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                ForEach(day.movements) { transaction in
                    RemoteMovementRow(transaction: transaction, showCents: showCents, hideBalances: hideBalances) {
                        detail = transaction
                    } onEdit: {
                        guard transaction.kind != .transfer else { return }
                        editing = transaction
                    } onDelete: {
                        deleteCandidate = transaction
                        isDeleteAlertPresented = true
                    }
                    .padding(.horizontal, 10)
                    .onAppear { store.loadNextPageIfNeeded(after: transaction.id) }
                }
            }
            .padding(.bottom, 18)
        }
        if store.isLoadingNextPage { ProgressView().padding(.vertical, 14) }
    }

    @ViewBuilder
    private var remoteUpcomingList: some View {
        if store.upcomingItems.isEmpty && !store.isLoading {
            NoResultsView(fullscreen: true)
        } else if !store.upcomingItems.isEmpty {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    HStack {
                        Text("IN ARRIVO")
                        Spacer()
                        Text(remoteSignedAmount(upcomingTotal, currencyCode: store.selectedCurrencyCode, exponent: store.selectedCurrencyExponent, showCents: showCents))
                            .monospacedDigit()
                            .layoutPriority(1)
                    }
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.SubtitleText)
                    Line().stroke(Color.Outline, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                ForEach(store.upcomingItems) { item in
                    RemoteMovementRow(upcoming: item, showCents: showCents, hideBalances: hideBalances)
                        .padding(.horizontal, 10)
                }
            }
            .padding(.bottom, 18)
        }
    }

    private var upcomingTotal: Int64 {
        store.upcomingItems.reduce(0) { total, item in
            switch item {
            case let .transaction(value): return total + (value.transaction.effectiveAmountMinor ?? 0)
            case let .recurrence(value): return total + (value.transactionKind == .income ? value.amountMinor : -value.amountMinor)
            }
        }
    }

    private var remoteFilterHeader: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                HStack(spacing: 10) {
                    Text(store.filter.title)
                        .font(.system(.body, design: .rounded).weight(.medium))
                    Button {
                        store.setFilter(.all)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.caption, design: .rounded).weight(.regular))
                            .foregroundStyle(Color.PrimaryText.opacity(0.7))
                    }
                    .accessibilityLabel("rimuovi filtro")
                }
                .padding(4)
                .padding(.horizontal, 6)
                .background(Color.AppSecondarySurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Spacer()
            }

            switch store.filter {
            case .type:
                Picker("Tipo", selection: $store.typeIsIncome) {
                    Text("Spese").tag(false)
                    Text("Entrate").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: store.typeIsIncome) { _ in store.setFilter(.type) }
            case .day:
                DatePicker("Giorno", selection: $store.selectedDay, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .onChange(of: store.selectedDay) { _ in store.setFilter(.day) }
            case .week:
                DatePicker("Settimana", selection: $store.selectedWeek, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .onChange(of: store.selectedWeek) { _ in store.setFilter(.week) }
            case .month:
                DatePicker("Mese", selection: $store.selectedMonth, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .onChange(of: store.selectedMonth) { _ in store.setFilter(.month) }
            case .category:
                Picker("Categoria", selection: Binding(get: { store.selectedCategoryID }, set: { store.selectedCategoryID = $0; store.setFilter(.category) })) {
                    Text("Tutte").tag(UUID?.none)
                    ForEach(store.categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .pickerStyle(.menu)
            case .all, .recurring, .upcoming:
                EmptyView()
            }
        }
        .padding(.horizontal, 25)
        .frame(height: 110, alignment: .top)
        .padding(.top, 10)
    }
}

private struct RemoteNativeFilterMenuBridge: UIViewControllerRepresentable {
    @Binding var filter: RemoteMovementFilter
    @Binding var hideBalances: Bool
    let selectedAccountID: UUID?
    let onFilter: (RemoteMovementFilter) -> Void
    let onTransfer: () -> Void

    func makeUIViewController(context: Context) -> RemoteFilterMenuViewController {
        RemoteFilterMenuViewController(
            filter: $filter,
            hideBalances: $hideBalances,
            selectedAccountID: selectedAccountID,
            onFilter: onFilter,
            onTransfer: onTransfer
        )
    }

    func updateUIViewController(_ viewController: RemoteFilterMenuViewController, context: Context) {
        viewController.filter = $filter
        viewController.hideBalances = $hideBalances
        viewController.selectedAccountID = selectedAccountID
        viewController.onFilter = onFilter
        viewController.onTransfer = onTransfer
        viewController.installMenuIfNeeded()
    }
}

private final class RemoteFilterMenuViewController: UIViewController {
    var filter: Binding<RemoteMovementFilter>
    var hideBalances: Binding<Bool>
    var selectedAccountID: UUID?
    var onFilter: (RemoteMovementFilter) -> Void
    var onTransfer: () -> Void

    private weak var installedNavigationItem: UINavigationItem?
    private weak var installedBarButtonItem: UIBarButtonItem?
    private weak var installedPrivacyButtonItem: UIBarButtonItem?
    private weak var installedTransferButtonItem: UIBarButtonItem?

    init(
        filter: Binding<RemoteMovementFilter>,
        hideBalances: Binding<Bool>,
        selectedAccountID: UUID?,
        onFilter: @escaping (RemoteMovementFilter) -> Void,
        onTransfer: @escaping () -> Void
    ) {
        self.filter = filter
        self.hideBalances = hideBalances
        self.selectedAccountID = selectedAccountID
        self.onFilter = onFilter
        self.onTransfer = onTransfer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installMenuIfNeeded()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        DispatchQueue.main.async { [weak self] in self?.installMenuIfNeeded() }
    }

    func installMenuIfNeeded() {
        guard let navigationItem = navigationController?.topViewController?.navigationItem else { return }

        if installedNavigationItem !== navigationItem
            || installedBarButtonItem == nil
            || installedPrivacyButtonItem == nil
            || installedTransferButtonItem == nil {
            let filterButton = UIBarButtonItem(
                image: UIImage(systemName: "line.3.horizontal.decrease"),
                menu: makeFilterMenu()
            )
            filterButton.accessibilityLabel = "Filtra"
            filterButton.accessibilityValue = filter.wrappedValue.title

            let privacyButton = UIBarButtonItem(
                image: UIImage(systemName: hideBalances.wrappedValue ? "eye.slash" : "eye"),
                style: .plain,
                target: self,
                action: #selector(toggleBalanceVisibility)
            )
            privacyButton.accessibilityLabel = hideBalances.wrappedValue ? "Mostra saldo" : "Nascondi saldo"
            privacyButton.accessibilityValue = hideBalances.wrappedValue ? "Saldo nascosto" : "Saldo visibile"

            let transferButton = UIBarButtonItem(
                image: UIImage(systemName: "arrow.left.arrow.right"),
                style: .plain,
                target: self,
                action: #selector(openTransfer)
            )
            transferButton.accessibilityLabel = "Nuovo trasferimento"
            transferButton.isEnabled = selectedAccountID != nil

            navigationItem.rightBarButtonItems = [filterButton, privacyButton]
            navigationItem.leftBarButtonItem = transferButton
            installedNavigationItem = navigationItem
            installedBarButtonItem = filterButton
            installedPrivacyButtonItem = privacyButton
            installedTransferButtonItem = transferButton
        } else {
            installedBarButtonItem?.menu = makeFilterMenu()
            installedBarButtonItem?.accessibilityValue = filter.wrappedValue.title
            installedPrivacyButtonItem?.image = UIImage(systemName: hideBalances.wrappedValue ? "eye.slash" : "eye")
            installedPrivacyButtonItem?.accessibilityLabel = hideBalances.wrappedValue ? "Mostra saldo" : "Nascondi saldo"
            installedPrivacyButtonItem?.accessibilityValue = hideBalances.wrappedValue ? "Saldo nascosto" : "Saldo visibile"
            installedTransferButtonItem?.isEnabled = selectedAccountID != nil
        }
    }

    @objc private func openTransfer() {
        onTransfer()
    }

    @objc private func toggleBalanceVisibility() {
        hideBalances.wrappedValue.toggle()
        installMenuIfNeeded()
    }

    private func makeFilterMenu() -> UIMenu {
        let actions = RemoteMovementFilter.allCases.map { option in
            UIAction(
                title: option.title,
                state: option == filter.wrappedValue ? .on : .off
            ) { [weak self] _ in
                self?.onFilter(option)
            }
        }
        return UIMenu(title: "Filtro", options: [.singleSelection], children: actions)
    }
}

private struct RemoteCompactBalanceToolbarTitle: View {
    let accountName: String
    let showCents: Bool
    let currencySymbol: String
    let netTotal: (value: Int64, positive: Bool)
    let currencyCode: String
    let currencyExponent: Int
    let hideBalances: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(accountName)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(Color.SubtitleText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(netTotal.positive ? currencySymbol : "-\(currencySymbol)")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.SubtitleText)
                    .layoutPriority(1)
                Text(remoteAmountDigits(abs(netTotal.value), currencyCode: currencyCode, exponent: currencyExponent, showCents: showCents))
                    .font(RemoteClashDisplayFont.font(size: 20))
                    .foregroundStyle(Color.PrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
                    .layoutPriority(0)
                    .blur(radius: hideBalances ? remotePrivacyBlurRadius : 0)
                    .opacity(hideBalances ? 0.72 : 1)
                    .animation(remotePrivacyTransition, value: hideBalances)
                    .accessibilityHidden(hideBalances)
            }
        }
        .lineLimit(1)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hideBalances ? "Saldo nascosto" : "\(accountName), saldo \(currencySymbol)\(remoteAmountDigits(abs(netTotal.value), currencyCode: currencyCode, exponent: currencyExponent, showCents: showCents))")
    }
}

@available(iOS 26.0, *)
private struct RemoteAccountPager: View {
    @EnvironmentObject private var store: FinancialRemoteStore
    @Binding var selectedAccountID: UUID?
    let hideBalances: Bool
    let showCents: Bool
    let collapseProgress: CGFloat
    let handoff: CGFloat

    private var pageControlReservedSpace: CGFloat {
        store.activeAccounts.count > 1 ? 24 : 0
    }

    var body: some View {
        TabView(selection: $selectedAccountID) {
            ForEach(store.activeAccounts) { account in
                RemoteAccountHeader(
                    account: account,
                    hideBalances: hideBalances,
                    showCents: showCents,
                    collapseProgress: collapseProgress,
                    handoff: handoff
                )
                .padding(.bottom, pageControlReservedSpace)
                    .tag(Optional(account.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 175 + pageControlReservedSpace)
    }
}

@available(iOS 26.0, *)
private struct RemoteAccountHeader: View {
    @EnvironmentObject private var store: FinancialRemoteStore
    let account: RemoteAccountDTO
    let hideBalances: Bool
    let showCents: Bool
    let collapseProgress: CGFloat
    let handoff: CGFloat

    private var snapshot: RemoteAccountSnapshotDTO? {
        store.selectedSnapshot?.id == account.id ? store.selectedSnapshot : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(account.name)
                .font(.system(size: 19 - (4 * collapseProgress), design: .rounded).weight(.medium))
                .foregroundStyle(Color.PrimaryText.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 8 - (4 * collapseProgress))

            if let snapshot {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(snapshot.balanceMinor >= 0 ? currencySymbol : "-\(currencySymbol)")
                        .font(.system(size: 34 - (8 * collapseProgress), design: .rounded))
                        .foregroundStyle(Color.SubtitleText)
                        .layoutPriority(1)
                    Text(remoteAmountDigits(abs(snapshot.balanceMinor), currencyCode: snapshot.currencyCode, exponent: snapshot.currencyExponent, showCents: showCents))
                        .font(RemoteClashDisplayFont.font(size: 84 - (56 * collapseProgress)))
                        .foregroundStyle(Color.PrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .allowsTightening(true)
                        .monospacedDigit()
                        .layoutPriority(0)
                        .blur(radius: hideBalances ? remotePrivacyBlurRadius : 0)
                        .opacity(hideBalances ? 0.72 : 1)
                        .animation(remotePrivacyTransition, value: hideBalances)
                }

                HStack {
                        Text("+\(remoteAmountDigits(store.summary.incomeMinor, currencyCode: snapshot.currencyCode, exponent: snapshot.currencyExponent, showCents: showCents))")
                        .font(.system(size: 24 - (6 * collapseProgress), design: .rounded).weight(.medium))
                        .minimumScaleFactor(0.5)
                        .monospacedDigit()
                        .foregroundStyle(Color.IncomeGreen)
                        .lineLimit(1)

                    DottedLine()
                        .stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                        .frame(width: 1.7, height: 15)
                        .foregroundStyle(Color.Outline)

                    Text("-\(remoteAmountDigits(store.summary.expensesMinor, currencyCode: snapshot.currencyCode, exponent: snapshot.currencyExponent, showCents: showCents))")
                        .font(.system(size: 24 - (6 * collapseProgress), design: .rounded).weight(.medium))
                        .minimumScaleFactor(0.5)
                        .monospacedDigit()
                        .foregroundStyle(Color.AlertRed)
                        .lineLimit(1)
                }
                .padding(.top, 8)
                .opacity(1 - handoff)
                .frame(height: 31 * (1 - handoff))
                .clipped()
                .blur(radius: hideBalances ? remoteSubheaderBlurRadius : 0)
                .opacity(hideBalances ? 0.72 : 1)
                .animation(remotePrivacyTransition, value: hideBalances)
                .accessibilityHidden(hideBalances)
            } else {
                ProgressView().padding(.top, 35)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(minHeight: 175)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hideBalances ? "\(account.name), saldo nascosto" : "\(account.name), saldo \(snapshot.map { remoteCurrencySymbol(for: $0.currencyCode) + remoteAmountDigits($0.balanceMinor, currencyCode: $0.currencyCode, exponent: $0.currencyExponent) } ?? "non disponibile")")
    }

    private var currencySymbol: String {
        Locale.current.localizedCurrencySymbol(forCurrencyCode: account.currencyCode) ?? account.currencyCode
    }
}

@available(iOS 26.0, *)
private struct RemoteMovementRow: View {
    let transaction: RemoteTransactionDTO?
    let upcoming: RemoteUpcomingItemDTO?
    let showCents: Bool
    let hideBalances: Bool
    let onDetail: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    init(transaction: RemoteTransactionDTO, showCents: Bool, hideBalances: Bool, onDetail: @escaping () -> Void, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.transaction = transaction
        self.upcoming = nil
        self.showCents = showCents
        self.hideBalances = hideBalances
        self.onDetail = onDetail
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    init(upcoming: RemoteUpcomingItemDTO, showCents: Bool, hideBalances: Bool) {
        self.transaction = nil
        self.upcoming = upcoming
        self.showCents = showCents
        self.hideBalances = hideBalances
        self.onDetail = {}
        self.onEdit = {}
        self.onDelete = {}
    }

    var body: some View {
        Button(action: onDetail) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.PrimaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.SubtitleText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let amount = effectiveAmount {
                    Text(remoteSignedAmount(amount, currencyCode: amountCurrencyCode, exponent: amountCurrencyExponent, showCents: showCents))
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(amount < 0 ? Color.AlertRed : amount > 0 ? Color.IncomeGreen : Color.SubtitleText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                        .blur(radius: hideBalances ? remotePrivacyBlurRadius : 0)
                        .opacity(hideBalances ? 0.72 : 1)
                        .animation(remotePrivacyTransition, value: hideBalances)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let transaction {
                if transaction.kind != .transfer { Button("Modifica", action: onEdit) }
                Button("Elimina", role: .destructive, action: onDelete)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let transaction, transaction.kind == .transfer {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.PrimaryText)
                .frame(width: 34, height: 34)
                .background(Color.AppSecondarySurface, in: Circle())
        } else if let transaction, let serviceID = transaction.subscription?.serviceID,
                  let service = SubscriptionServiceCatalog.service(forID: serviceID) {
            SubscriptionLogoView(service: service, size: 34)
                .fixedSize(horizontal: true, vertical: true)
        } else if let transaction {
            CategoryLogIconView(
                iconIdentifier: transaction.category?.iconIdentifier ?? "sf:tag.fill",
                categoryName: transaction.category?.name,
                colour: transaction.category?.color ?? "#FFFFFF",
                future: false
            )
            .fixedSize(horizontal: true, vertical: true)
            .overlay(alignment: .bottomTrailing) {
                if transaction.recurrence != nil {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.DarkIcon)
                        .padding(3)
                        .background(Color.AppSecondarySurface, in: RoundedRectangle(cornerRadius: 6))
                        .offset(x: 5, y: 5)
                }
            }
        } else {
            CategoryLogIconView(
                iconIdentifier: upcomingCategory?.iconIdentifier ?? "sf:clock.arrow.circlepath",
                categoryName: upcomingCategory?.name,
                colour: upcomingCategory?.color ?? "#FFFFFF",
                future: true
            )
            .fixedSize(horizontal: true, vertical: true)
        }
    }

    private var subtitle: String {
        if let transfer = transaction?.transfer {
            return "\(transfer.sourceAccountName) → \(transfer.destinationAccountName)"
        }
        if let upcoming {
            switch upcoming {
            case let .transaction(item): return remoteDateLabel(item.effectiveDate)
            case let .recurrence(item): return remoteDateLabel(item.scheduledDate)
            }
        }
        return transaction.map { remoteTimeLabel($0.occurredAt) } ?? ""
    }

    private var displayTitle: String {
        if let upcoming {
            switch upcoming {
            case let .transaction(item): return displayTitle(for: item.transaction)
            case let .recurrence(item): return item.title ?? item.category?.name ?? (item.transactionKind == .income ? "Entrata" : "Spesa")
            }
        }
        guard let transaction else { return "" }
        return displayTitle(for: transaction)
    }

    private func displayTitle(for transaction: RemoteTransactionDTO) -> String {
        if transaction.kind == .income, transaction.title.caseInsensitiveCompare("income") == .orderedSame {
            return "Entrata"
        }
        if transaction.kind == .expense, transaction.title.caseInsensitiveCompare("expense") == .orderedSame {
            return "Spesa"
        }
        return transaction.title
    }

    private var effectiveAmount: Int64? {
        if let transaction { return transaction.effectiveAmountMinor }
        guard let upcoming else { return nil }
        switch upcoming {
        case let .transaction(item): return item.transaction.effectiveAmountMinor
        case let .recurrence(item): return item.transactionKind == .income ? item.amountMinor : -item.amountMinor
        }
    }

    private var upcomingCategory: RemoteCategoryBriefDTO? {
        guard case let .recurrence(item) = upcoming else { return nil }
        return item.category
    }

    private var amountCurrencyCode: String {
        if let transaction { return transaction.currencyCode }
        if case let .recurrence(item) = upcoming { return item.currencyCode }
        if case let .transaction(item) = upcoming { return item.transaction.currencyCode }
        return "EUR"
    }

    private var amountCurrencyExponent: Int {
        if let transaction { return transaction.currencyExponent }
        if case let .recurrence(item) = upcoming { return item.currencyExponent }
        if case let .transaction(item) = upcoming { return item.transaction.currencyExponent }
        return 2
    }
}

@available(iOS 26.0, *)
struct RemoteTransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinancialRemoteStore
    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) private var showCents = true
    let transaction: RemoteTransactionDTO
    let selectedAccountID: UUID?

    var body: some View {
        Group {
            if #available(iOS 16.4, *) {
                detailContent
                    .presentationDetents([.fraction(0.58)])
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.scrolls)
            } else if #available(iOS 16.0, *) {
                detailContent
                    .presentationDetents([.fraction(0.58)])
                    .presentationDragIndicator(.visible)
            } else {
                detailContent
            }
        }
    }

    private var detailContent: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        if let serviceID = transaction.subscription?.serviceID,
                           let service = SubscriptionServiceCatalog.service(forID: serviceID) {
                            SubscriptionLogoView(service: service, size: 48)
                        }

                        Text(transaction.kind == .transfer ? "Trasferimento" : displayTitle)
                            .font(.system(.title2, design: .rounded).weight(.medium))
                            .foregroundStyle(Color.PrimaryText)

                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text("\(amountPrefix)\(currencySymbol)")
                                .font(.system(.headline, design: .rounded).weight(.medium))
                                .foregroundStyle(Color.SubtitleText)

                            Text(amountDigits)
                                .font(RemoteClashDisplayFont.font(size: 34))
                                .foregroundStyle(amountColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                                .allowsTightening(true)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Importo, \(amountPrefix)\(currencySymbol)\(amountDigits)")
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)

                    VStack(spacing: 0) {
                        if let category = transaction.category, transaction.kind != .transfer {
                            detailRow(label: "Categoria", value: category.name)
                        }
                        if transaction.kind != .transfer, let accountName {
                            detailRow(label: "Conto", value: accountName)
                        }
                        if let transfer = transaction.transfer {
                            detailRow(label: "Da", value: transfer.sourceAccountName)
                            detailRow(label: "A", value: transfer.destinationAccountName)
                        }
                        detailRow(label: "Data", value: remoteDateLabel(transaction.localDay))
                        detailRow(label: "Ora", value: remoteTimeLabel(transaction.occurredAt))
                    }

                    if let displayNote {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nota")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundStyle(Color.SubtitleText)
                            Text(displayNote)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.PrimaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var amountDigits: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = showCents ? transaction.currencyExponent : 0
        formatter.maximumFractionDigits = showCents ? transaction.currencyExponent : 0
        return formatter.string(from: NSNumber(value: Double(abs(displayedAmount ?? 0)) / pow(10, Double(transaction.currencyExponent)))) ?? "0"
    }

    private var amountPrefix: String {
        guard let displayedAmount else { return "" }
        return displayedAmount >= 0 ? "+" : "-"
    }

    private var currencySymbol: String {
        remoteCurrencySymbol(for: transaction.currencyCode)
    }

    private var amountColor: Color {
        guard let amount = displayedAmount else { return Color.SubtitleText }
        return amount < 0 ? Color.AlertRed : Color.IncomeGreen
    }

    private var accountName: String? {
        store.accounts.first(where: { $0.id == transaction.accountID })?.name
    }

    private var displayTitle: String {
        if transaction.kind == .income, transaction.title.caseInsensitiveCompare("income") == .orderedSame {
            return "Entrata"
        }
        if transaction.kind == .expense, transaction.title.caseInsensitiveCompare("expense") == .orderedSame {
            return "Spesa"
        }
        return transaction.title
    }

    private var displayNote: String? {
        guard let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return nil }
        guard transaction.subscription == nil else {
            let serviceID = transaction.subscription?.serviceID ?? ""
            return SubscriptionDisplayIdentity.normalized(note) == SubscriptionDisplayIdentity.normalized(serviceID) ? nil : note
        }
        return note
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(Color.SubtitleText)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }

    private var displayedAmount: Int64? {
        if let amount = transaction.effectiveAmountMinor { return amount }
        guard transaction.kind == .transfer, let transfer = transaction.transfer else { return transaction.kind == .income ? transaction.amountMinor : -transaction.amountMinor }
        return selectedAccountID == transfer.destinationAccountID ? transaction.amountMinor : -transaction.amountMinor
    }
}

enum RemoteTransactionEditorMode: String, CaseIterable, Identifiable {
    case expense, income, subscription
    var id: String { rawValue }
    var title: String { self == .expense ? "Spesa" : self == .income ? "Entrata" : "Abbonamento" }
    var kind: RemoteTransactionKind { self == .expense ? .expense : .income }
}

@available(iOS 26.0, *)
struct RemoteSubscriptionEditorView: View {
    let subscription: RemoteSubscriptionDTO?

    var body: some View {
        RemoteMovementEditorSurface(kind: .subscription(subscription), initialAccountID: subscription?.accountID)
    }
}

@available(iOS 26.0, *)
struct RemoteTransactionEditorView: View {
    let transaction: RemoteTransactionDTO?
    let initialAccountID: UUID?

    var body: some View {
        RemoteMovementEditorSurface(kind: .transaction(transaction), initialAccountID: initialAccountID)
    }
}

@available(iOS 26.0, *)
struct RemoteTransferEditorView: View {
    var body: some View {
        RemoteMovementEditorSurface(kind: .transfer, initialAccountID: nil)
    }
}

@available(iOS 26.0, *)
private struct RemoteMovementEditorSurface: View {
    enum Kind {
        case transaction(RemoteTransactionDTO?)
        case transfer
        case subscription(RemoteSubscriptionDTO?)
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinancialRemoteStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var amountFocused: Bool

    let kind: Kind
    let initialAccountID: UUID?

    @State private var mode: RemoteTransactionEditorMode
    @State private var accountID: UUID?
    @State private var sourceID: UUID?
    @State private var destinationID: UUID?
    @State private var categoryID: UUID?
    @State private var amountText: String
    @State private var note = ""
    @State private var noteDraft = ""
    @State private var merchant = ""
    @State private var occurredAt: Date
    @State private var repeatType = 0
    @State private var repeatCoefficient = 1
    @State private var showNoteSheet = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var subscriptionService: SubscriptionCatalogService?
    @State private var subscriptionIsCustom = false
    @State private var subscriptionCustomName = ""
    @State private var subscriptionCadence: SubscriptionCadence = .monthly
    @State private var subscriptionStartDate = Date.now

    init(kind: Kind, initialAccountID: UUID?) {
        self.kind = kind
        self.initialAccountID = initialAccountID
        let transaction: RemoteTransactionDTO?
        let subscription: RemoteSubscriptionDTO?
        switch kind {
        case let .transaction(value): transaction = value; subscription = nil
        case .transfer: transaction = nil; subscription = nil
        case let .subscription(value): transaction = nil; subscription = value
        }
        _mode = State(initialValue: subscription != nil ? .subscription : (transaction?.kind == .income ? .income : .expense))
        _accountID = State(initialValue: subscription?.accountID ?? transaction?.accountID ?? initialAccountID)
        _sourceID = State(initialValue: transaction?.transfer?.sourceAccountID ?? initialAccountID)
        _destinationID = State(initialValue: transaction?.transfer?.destinationAccountID)
        _categoryID = State(initialValue: transaction?.category?.id)
        _amountText = State(initialValue: transaction.map { decimalString($0.amountMinor, exponent: $0.currencyExponent) } ?? "")
        _note = State(initialValue: transaction?.note ?? "")
        _noteDraft = State(initialValue: transaction?.note ?? "")
        _merchant = State(initialValue: transaction?.merchant ?? "")
        _occurredAt = State(initialValue: transaction?.occurredAt ?? .now)
        _repeatType = State(initialValue: transaction?.recurrence == nil ? 0 : 1)
        _repeatCoefficient = State(initialValue: 1)
        _subscriptionService = State(initialValue: subscription.flatMap { SubscriptionServiceCatalog.service(forID: $0.serviceID) })
        _subscriptionIsCustom = State(initialValue: subscription?.customName != nil)
        _subscriptionCustomName = State(initialValue: subscription?.customName ?? "")
        _subscriptionCadence = State(initialValue: Self.localCadence(subscription?.cadence) ?? .monthly)
        _subscriptionStartDate = State(initialValue: Self.date(from: subscription?.billingAnchor) ?? .now)
    }

    private var transaction: RemoteTransactionDTO? {
        if case let .transaction(value) = kind { return value }
        return nil
    }

    private var subscription: RemoteSubscriptionDTO? {
        if case let .subscription(value) = kind { return value }
        return nil
    }

    private var isTransfer: Bool {
        if case .transfer = kind { return true }
        return false
    }

    private var isSubscription: Bool {
        if case .subscription = kind { return true }
        return false
    }

    private var isEditing: Bool { transaction != nil || subscription != nil }

    var body: some View {
        NavigationStack { editorContent }
            .dynamicTypeSize(...DynamicTypeSize.accessibility5)
            .modifier(RemoteEditorSheetPresentation(compact: isTransfer))
            .onAppear {
                normalizeSelections()
                syncRecurrenceSelection()
            }
            .onChange(of: store.activeAccounts.count) { _ in normalizeSelections() }
            .onChange(of: sourceID) { _ in normalizeSelections() }
            .alert("Errore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Impossibile salvare il movimento.") }
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                typeSelector
                amountSection
                if mode != .subscription && !isTransfer { categoryCarousel }
                if mode == .subscription { subscriptionContent } else { detailsSection }
            }
            .padding(.horizontal, 17)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva", action: save)
                    .disabled(isSaving || !canSave)
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
        .sheet(isPresented: $showNoteSheet, onDismiss: { noteDraft = note }) {
            RemoteTransactionNoteSheet(note: $note, draft: $noteDraft, isPresented: $showNoteSheet)
        }
    }

    private var title: String {
        if isTransfer { return isEditing ? "Modifica trasferimento" : "Nuovo trasferimento" }
        if mode == .subscription { return isEditing ? "Modifica abbonamento" : "Nuovo abbonamento" }
        if isEditing { return "Modifica movimento" }
        return "Nuovo movimento"
    }

    @ViewBuilder private var typeSelector: some View {
        if isTransfer {
            Text("Trasferimento")
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Tipo di movimento: Trasferimento")
        } else if isSubscription {
            Text("Abbonamento")
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Tipo di movimento: Abbonamento")
        } else {
            Picker("Tipo di movimento", selection: $mode) {
                Text("Spesa").tag(RemoteTransactionEditorMode.expense)
                Text("Entrata").tag(RemoteTransactionEditorMode.income)
                if !isEditing { Text("Abbonamento").tag(RemoteTransactionEditorMode.subscription) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Tipo di movimento")
            .onChange(of: mode) { _ in categoryID = nil }
        }
    }

    private var amountSection: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(remoteCurrencySymbol(for: selectedAccount?.currencyCode ?? "EUR"))
                .font(.system(size: dynamicTypeSize >= .xxLarge ? 42 : 48, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            TextField("0,00", text: amountBinding)
                .focused($amountFocused)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .font(.system(size: dynamicTypeSize >= .xxLarge ? 64 : 80, weight: .regular, design: .rounded))
                .minimumScaleFactor(0.42)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .accessibilityLabel("Importo")
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { amountFocused = true }
        .padding(.vertical, 4)
    }

    private var categoryCarousel: some View {
        Group {
            if filteredCategories.isEmpty {
                Button { store.deferredFeatureMessage = "Aggiungi una categoria dalle Impostazioni." } label: {
                    Label("Aggiungi categoria", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 14)
                        .background(Color.AppSecondarySurface, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(filteredCategories) { category in
                                Button {
                                    categoryID = category.id
                                } label: {
                                    HStack(spacing: 7) {
                                        CategoryIconView(
                                            descriptor: CategoryIconPresentation.descriptor(for: category.iconIdentifier),
                                            role: .inline,
                                            accessibilityLabel: category.name
                                        )
                                        Text(category.name)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                        if category.id == categoryID {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                        }
                                    }
                                    .font(.body.weight(category.id == categoryID ? .semibold : .regular))
                                    .frame(minHeight: 44)
                                    .padding(.horizontal, 13)
                                    .background(Color.AppSecondarySurface, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(category.name)
                                .accessibilityAddTraits(category.id == categoryID ? .isSelected : [])
                                .id(category.id)
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 52)
                    .onAppear {
                        if let categoryID { proxy.scrollTo(categoryID, anchor: .center) }
                    }
                    .onChange(of: categoryID) { value in
                        guard let value else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(value, anchor: .center) }
                    }
                }
            }
        }
    }

    private var subscriptionContent: some View {
        GroupBox {
            VStack(spacing: 10) {
                NavigationLink {
                    SubscriptionServicePickerView(
                        selectedService: $subscriptionService,
                        isCustom: $subscriptionIsCustom,
                        customName: $subscriptionCustomName
                    )
                } label: {
                    HStack(spacing: 12) {
                        SubscriptionLogoView(service: subscriptionService, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Servizio")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(subscriptionIsCustom && !subscriptionCustomName.isEmpty ? subscriptionCustomName : subscriptionService?.displayName ?? "Scegli servizio")
                                .foregroundStyle(subscriptionService == nil && !subscriptionIsCustom ? .secondary : .primary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 48)
                }
                .buttonStyle(.plain)

                if subscriptionIsCustom {
                    TextField("Nome del servizio", text: $subscriptionCustomName)
                        .textFieldStyle(.roundedBorder)
                }

                RemoteEditorRow(title: "Frequenza", systemImage: "repeat") {
                    Picker("Frequenza", selection: $subscriptionCadence) {
                        Text("Settimanale").tag(SubscriptionCadence.weekly)
                        Text("Mensile").tag(SubscriptionCadence.monthly)
                        Text("Annuale").tag(SubscriptionCadence.yearly)
                    }
                    .labelsHidden()
                    .tint(.secondary)
                }
                RemoteEditorRow(title: "Data di inizio", systemImage: "calendar") {
                    DatePicker("Data di inizio", selection: $subscriptionStartDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "it_IT"))
                }
                RemoteEditorRow(title: "Conto", systemImage: "building.columns.fill") {
                    RemoteAccountMenu(accounts: store.activeAccounts, selection: $accountID)
                }
                noteRow
            }
        }
    }

    private var detailsSection: some View {
        GroupBox {
            VStack(spacing: 10) {
                if !isTransfer {
                    RemoteEditorRow(title: "Data e ora", systemImage: "calendar") {
                        DatePicker("Data e ora", selection: $occurredAt)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .environment(\.locale, Locale(identifier: "it_IT"))
                    }
                }
                if isTransfer {
                    RemoteEditorRow(title: "Da", systemImage: "arrow.up.right") {
                        RemoteAccountMenu(accounts: store.activeAccounts, selection: $sourceID)
                    }
                    RemoteEditorRow(title: "A", systemImage: "arrow.down.left") {
                        RemoteAccountMenu(accounts: destinationAccounts, selection: $destinationID)
                    }
                } else {
                    RemoteEditorRow(title: "Conto", systemImage: "building.columns.fill") {
                        RemoteAccountMenu(accounts: store.activeAccounts, selection: $accountID)
                    }
                }
                if !isTransfer && mode == .expense { recurrenceRow }
                noteRow
            }
        }
    }

    private var recurrenceRow: some View {
        RemoteEditorRow(title: "Ripeti", systemImage: "repeat") {
            Menu {
                recurrenceChoice("Mai", type: 0, coefficient: 1)
                recurrenceChoice("Ogni giorno", type: 1, coefficient: 1)
                recurrenceChoice("Ogni settimana", type: 2, coefficient: 1)
                recurrenceChoice("Ogni mese", type: 3, coefficient: 1)
                Divider()
                Button("Personalizzata…") { store.deferredFeatureMessage = "La ricorrenza personalizzata sarà disponibile in un prossimo aggiornamento." }
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
            .tint(.secondary)
        }
    }

    private var noteRow: some View {
        RemoteEditorRow(title: "Nota", systemImage: "note.text") {
            HStack(spacing: 8) {
                if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Button(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Aggiungi" : "Modifica") {
                    noteDraft = note
                    showNoteSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
                if repeatType == type && (type == 0 || repeatCoefficient == coefficient) { Image(systemName: "checkmark") }
            }
        }
    }

    private var repeatSummary: String {
        switch repeatType {
        case 1: return "Ogni giorno"
        case 2: return "Ogni settimana"
        case 3: return "Ogni mese"
        default: return "Mai"
        }
    }

    private var filteredCategories: [RemoteCategoryDTO] {
        store.categories.filter { $0.income == (mode == .income) }
    }

    private var destinationAccounts: [RemoteAccountDTO] {
        store.activeAccounts.filter { $0.id != sourceID }
    }

    private var selectedAccount: RemoteAccountDTO? {
        let id = isTransfer ? sourceID : accountID
        return id.flatMap { selectedID in store.activeAccounts.first(where: { $0.id == selectedID }) }
    }

    private var amountBinding: Binding<String> {
        Binding(get: { amountText }, set: { amountText = clampedAmountText($0) })
    }

    private var amountMinor: Int64? {
        guard let selectedAccount else { return nil }
        return parseMinorUnits(amountText, exponent: selectedAccount.currencyExponent)
    }

    private var canSave: Bool {
        guard let amountMinor, amountMinor > 0 else { return false }
        if isTransfer {
            guard let source = sourceAccount, let destination = destinationAccount else { return false }
            return source.id != destination.id && source.currencyCode == destination.currencyCode
        }
        if mode == .subscription {
            let customName = subscriptionCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
            return accountID != nil && ((subscriptionIsCustom && !customName.isEmpty) || (!subscriptionIsCustom && subscriptionService != nil))
        }
        return accountID != nil && (mode == .income || categoryID != nil)
    }

    private var sourceAccount: RemoteAccountDTO? {
        sourceID.flatMap { id in store.activeAccounts.first(where: { $0.id == id }) }
    }

    private var destinationAccount: RemoteAccountDTO? {
        destinationID.flatMap { id in store.activeAccounts.first(where: { $0.id == id }) }
    }

    private func normalizeSelections() {
        if isTransfer {
            sourceID = sourceID ?? store.selectedAccountID ?? store.activeAccounts.first?.id
            if destinationID == sourceID { destinationID = nil }
            destinationID = destinationID ?? destinationAccounts.first?.id
        } else {
            accountID = accountID ?? store.selectedAccountID ?? store.activeAccounts.first?.id
        }
    }

    private func syncRecurrenceSelection() {
        guard let ruleID = transaction?.recurrence?.ruleID,
              let rule = store.recurrenceRules.first(where: { $0.id == ruleID }) else { return }
        repeatType = switch rule.cadence {
        case .daily: 1
        case .weekly: 2
        case .monthly: 3
        }
        repeatCoefficient = rule.cadenceInterval
    }

    private func clampedAmountText(_ value: String) -> String {
        guard let separator = value.firstIndex(of: ",") ?? value.firstIndex(of: ".") else { return value }
        let fractionStart = value.index(after: separator)
        guard value[fractionStart...].count > 2 else { return value }
        return String(value[..<value.index(fractionStart, offsetBy: 2)])
    }

    private func save() {
        if mode == .subscription { saveSubscription(); return }
        if isTransfer {
            saveTransfer()
        } else {
            saveTransaction()
        }
    }

    private func saveSubscription() {
        guard let accountID,
              let account = store.activeAccounts.first(where: { $0.id == accountID }),
              let amountMinor,
              let billingAnchor = Self.remoteDateOnly(from: subscriptionStartDate) else { return }
        let customName = subscriptionIsCustom ? subscriptionCustomName.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let serviceID = subscriptionIsCustom ? nil : subscriptionService?.id
        guard serviceID != nil || customName != nil else { return }
        isSaving = true
        Task {
            do {
                if let subscription {
                    _ = try await store.updateSubscription(subscription.id, payload: RemoteSubscriptionUpdatePayload(
                        accountID: accountID,
                        serviceID: serviceID,
                        customName: customName,
                        amountMinor: amountMinor,
                        currencyCode: account.currencyCode,
                        currencyExponent: account.currencyExponent,
                        cadence: Self.remoteCadence(subscriptionCadence),
                        cadenceInterval: 1,
                        billingAnchor: billingAnchor,
                        note: note.isEmpty ? nil : note
                    ))
                } else {
                    _ = try await store.createSubscription(RemoteSubscriptionCreatePayload(
                        accountID: accountID,
                        serviceID: serviceID,
                        customName: customName,
                        amountMinor: amountMinor,
                        currencyCode: account.currencyCode,
                        currencyExponent: account.currencyExponent,
                        cadence: Self.remoteCadence(subscriptionCadence),
                        billingAnchor: billingAnchor,
                        note: note.isEmpty ? nil : note
                    ))
                }
                dismiss()
            } catch {
                errorMessage = "Impossibile salvare l'abbonamento. Riprova."
            }
            isSaving = false
        }
    }

    private static func remoteCadence(_ cadence: SubscriptionCadence) -> RemoteSubscriptionCadence {
        switch cadence {
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        }
    }

    private static func localCadence(_ cadence: RemoteSubscriptionCadence?) -> SubscriptionCadence? {
        switch cadence {
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        case .none: return nil
        }
    }

    private static func date(from date: RemoteDateOnly?) -> Date? {
        guard let date else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = date.year
        components.month = date.month
        components.day = date.day
        return components.calendar?.date(from: components)
    }

    private static func remoteDateOnly(from date: Date) -> RemoteDateOnly? {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return try? RemoteDateOnly(year: year, month: month, day: day)
    }

    private func saveTransaction() {
        guard let accountID, let account = store.activeAccounts.first(where: { $0.id == accountID }), let amountMinor else { return }
        isSaving = true
        Task {
            do {
                if mode == .expense && (repeatType > 0 || transaction?.recurrence != nil) {
                    try await saveRemoteRecurrence(account: account, accountID: accountID, amountMinor: amountMinor)
                } else if let transaction {
                    _ = try await store.updateTransaction(transaction.id, payload: RemoteTransactionUpdatePayload(
                        kind: mode.kind,
                        accountID: accountID,
                        amountMinor: amountMinor,
                        currencyCode: account.currencyCode,
                        currencyExponent: account.currencyExponent,
                        occurredAt: occurredAt,
                        categoryID: categoryID,
                        note: note.isEmpty ? nil : note,
                        merchant: merchant.isEmpty ? nil : merchant,
                        origin: "manual",
                        reviewStatus: "confirmed"
                    ))
                } else {
                    _ = try await store.createTransaction(RemoteTransactionCreatePayload(
                        kind: mode.kind,
                        accountID: accountID,
                        amountMinor: amountMinor,
                        currencyCode: account.currencyCode,
                        currencyExponent: account.currencyExponent,
                        occurredAt: occurredAt,
                        categoryID: categoryID,
                        note: note.isEmpty ? nil : note,
                        merchant: merchant.isEmpty ? nil : merchant
                    ))
                }
                dismiss()
            } catch {
                errorMessage = "Impossibile salvare il movimento. Riprova."
            }
            isSaving = false
        }
    }

    private func saveRemoteRecurrence(account: RemoteAccountDTO, accountID: UUID, amountMinor: Int64) async throws {
        let ruleID = transaction?.recurrence?.ruleID
        if repeatType == 0 {
            if let ruleID { try await store.cancelRecurrence(ruleID) }
            dismiss()
            return
        }

        let cadence = remoteRecurrenceCadence
        let title = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        if let ruleID {
            _ = try await store.updateRecurrence(ruleID, payload: RemoteRecurrenceUpdatePayload(
                accountID: accountID,
                categoryID: categoryID,
                kind: .expense,
                amountMinor: amountMinor,
                currencyCode: account.currencyCode,
                currencyExponent: account.currencyExponent,
                title: title,
                note: title,
                merchant: merchant.isEmpty ? nil : merchant,
                cadence: cadence,
                cadenceInterval: repeatCoefficient
            ))
        } else {
            guard let anchorDate = Self.remoteDateOnly(from: occurredAt) else { return }
            _ = try await store.createRecurrence(RemoteRecurrenceCreatePayload(
                accountID: accountID,
                categoryID: categoryID,
                kind: .expense,
                amountMinor: amountMinor,
                currencyCode: account.currencyCode,
                currencyExponent: account.currencyExponent,
                title: title,
                note: title,
                merchant: merchant.isEmpty ? nil : merchant,
                cadence: cadence,
                cadenceInterval: repeatCoefficient,
                anchorDate: anchorDate
            ))
        }
        dismiss()
    }

    private var remoteRecurrenceCadence: RemoteRecurrenceCadence {
        switch repeatType {
        case 1: return .daily
        case 2: return .weekly
        default: return .monthly
        }
    }

    private func saveTransfer() {
        guard let source = sourceAccount, let destination = destinationAccount, let amountMinor else { return }
        isSaving = true
        Task {
            do {
                _ = try await store.createTransfer(RemoteTransferCreatePayload(
                    sourceAccountID: source.id,
                    destinationAccountID: destination.id,
                    amountMinor: amountMinor,
                    currencyCode: source.currencyCode,
                    currencyExponent: source.currencyExponent,
                    occurredAt: Date.now,
                    note: note.isEmpty ? nil : note
                ))
                dismiss()
            } catch {
                errorMessage = "Impossibile creare il trasferimento. Riprova."
            }
            isSaving = false
        }
    }
}

@available(iOS 26.0, *)
private struct RemoteEditorSheetPresentation: ViewModifier {
    let compact: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if compact {
            content
                .presentationDetents([.fraction(0.52)])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(AnyShapeStyle(Color.AppPageBackground.opacity(0.14)))
        } else {
            content
                .presentationDetents([.height(600), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(AnyShapeStyle(Color.AppPageBackground.opacity(0.14)))
        }
    }
}

@available(iOS 26.0, *)
private struct RemoteAccountMenu: View {
    let accounts: [RemoteAccountDTO]
    @Binding var selection: UUID?

    private var selectedAccount: RemoteAccountDTO? {
        selection.flatMap { id in accounts.first(where: { $0.id == id }) }
    }

    var body: some View {
        Menu {
            ForEach(accounts) { account in
                Button { selection = account.id } label: {
                    Label(account.name, systemImage: Sa7totSymbolResolver.resolved(account.iconName))
                }
            }
        } label: {
            Label(
                selectedAccount?.name ?? "Seleziona conto",
                systemImage: Sa7totSymbolResolver.resolved(selectedAccount?.iconName ?? "building.columns.fill")
            )
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.PrimaryText)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.AppSecondarySurface, in: RoundedRectangle(cornerRadius: 11.5, style: .continuous))
        }
        .accessibilityLabel("Conto: \(selectedAccount?.name ?? "Seleziona conto")")
    }
}

@available(iOS 26.0, *)
private struct RemoteTransactionNoteSheet: View {
    @Binding var note: String
    @Binding var draft: String
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
                        .background(Color.AppSecondarySurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: draft) { value in
                            if value.count > 50 { draft = String(value.prefix(50)) }
                        }
                        .accessibilityLabel("Nota")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .navigationTitle("Nota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        note = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        isPresented = false
                    }
                }
            }
        }
        .onAppear { focused = true }
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }
}

@available(iOS 26.0, *)
struct RemoteAccountListView: View {
    @EnvironmentObject private var store: FinancialRemoteStore
    @State private var showingNewAccount = false
    @State private var editingAccount: RemoteAccountDTO?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if store.accounts.isEmpty {
                ContentUnavailableView("Nessun conto", systemImage: "building.columns", description: Text("Tocca + per aggiungere il primo conto."))
            } else {
                ForEach(store.accounts) { account in
                    Button { editingAccount = account } label: {
                        HStack(spacing: 12) {
                            Image(systemName: account.iconName)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(Color.PrimaryText)
                                .frame(width: 38, height: 38)
                                .background(Color(hex: account.color), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.name)
                                Text(account.isArchived ? "Archiviato" : account.type)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(remoteAmount(account.openingBalanceMinor, currencyCode: account.currencyCode, exponent: account.currencyExponent))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .opacity(account.isArchived ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !account.isArchived {
                            Button {
                                Task {
                                    do { try await store.archiveAccount(account.id) }
                                    catch { errorMessage = "Impossibile archiviare il conto." }
                                }
                            } label: {
                                Label("Archivia", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Conti")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewAccount = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nuovo conto")
            }
        }
        .sheet(isPresented: $showingNewAccount) {
            RemoteAccountEditorView(account: nil).environmentObject(store)
        }
        .sheet(item: $editingAccount) { account in
            RemoteAccountEditorView(account: account).environmentObject(store)
        }
        .alert("Errore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "Impossibile modificare il conto.") }
        .task { await store.bootstrapIfNeeded() }
    }
}

@available(iOS 26.0, *)
struct RemoteAccountEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinancialRemoteStore
    let account: RemoteAccountDTO?

    @State private var name: String
    @State private var type: String
    @State private var currencyCode: String
    @State private var openingBalance: String
    @State private var iconName: String
    @State private var color: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(account: RemoteAccountDTO?) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? "other")
        _currencyCode = State(initialValue: account?.currencyCode ?? "EUR")
        _openingBalance = State(initialValue: account.map { decimalString($0.openingBalanceMinor, exponent: $0.currencyExponent) } ?? "0")
        _iconName = State(initialValue: account?.iconName ?? "building.columns.fill")
        _color = State(initialValue: account?.color ?? "#5E7CE2")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $name)
                TextField("Tipo", text: $type)
                TextField("Valuta", text: $currencyCode).textInputAutocapitalization(.characters)
                TextField("Saldo iniziale", text: $openingBalance).keyboardType(.decimalPad)
                TextField("Icona SF Symbol", text: $iconName)
                TextField("Colore", text: $color)
            }
            .navigationTitle(account == nil ? "Nuovo conto" : "Modifica conto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva", action: save).disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .alert("Errore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "Impossibile salvare il conto.") }
        }
    }

    private func save() {
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let amount = parseMinorUnits(openingBalance, exponent: account?.currencyExponent ?? 2) ?? 0
        guard normalizedCurrency.count == 3 else {
            errorMessage = "Controlla valuta e saldo iniziale."
            return
        }
        isSaving = true
        Task {
            do {
                if let account {
                    try await store.updateAccount(account.id, payload: RemoteAccountUpdatePayload(name: name, type: type, openingBalanceMinor: amount, iconName: iconName, color: color))
                } else {
                    try await store.createAccount(RemoteAccountCreatePayload(name: name, type: type, currencyCode: normalizedCurrency, currencyExponent: 2, openingBalanceMinor: amount, iconName: iconName, color: color))
                }
                dismiss()
            } catch {
                errorMessage = "Impossibile salvare il conto. Riprova."
            }
            isSaving = false
        }
    }
}

@available(iOS 26.0, *)
struct RemoteCategoryListView: View {
    @EnvironmentObject private var store: FinancialRemoteStore
    @State private var showingNewCategory = false
    @State private var editingCategory: RemoteCategoryDTO?
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(store.categories) { category in
                Button { editingCategory = category } label: {
                    HStack(spacing: 12) {
                        Image(systemName: category.iconIdentifier.replacingOccurrences(of: "sf:", with: ""))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(Color.PrimaryText)
                            .background(Color(hex: category.color), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(category.name)
                        Spacer()
                        Text(category.income ? "Entrata" : "Spesa")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task {
                            do { try await store.deleteCategory(category.id) }
                            catch { errorMessage = "Impossibile eliminare la categoria." }
                        }
                    } label: { Label("Elimina", systemImage: "trash") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Categorie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewCategory = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nuova categoria")
            }
        }
        .sheet(isPresented: $showingNewCategory) { RemoteCategoryEditorView(category: nil).environmentObject(store) }
        .sheet(item: $editingCategory) { category in RemoteCategoryEditorView(category: category).environmentObject(store) }
        .alert("Errore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Impossibile modificare la categoria.") }
        .task { await store.bootstrapIfNeeded() }
    }
}

@available(iOS 26.0, *)
struct RemoteCategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinancialRemoteStore
    let category: RemoteCategoryDTO?
    @State private var name: String
    @State private var income: Bool
    @State private var iconIdentifier: String
    @State private var color: String
    @State private var errorMessage: String?

    init(category: RemoteCategoryDTO?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _income = State(initialValue: category?.income ?? false)
        _iconIdentifier = State(initialValue: category?.iconIdentifier ?? "sf:tag.fill")
        _color = State(initialValue: category?.color ?? "#FFFFFF")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $name)
                Picker("Tipo", selection: $income) {
                    Text("Spesa").tag(false)
                    Text("Entrata").tag(true)
                }
                TextField("Icona SF Symbol", text: $iconIdentifier)
                TextField("Colore", text: $color)
            }
            .navigationTitle(category == nil ? "Nuova categoria" : "Modifica categoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .alert("Errore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Impossibile salvare la categoria.") }
        }
    }

    private func save() {
        Task {
            do {
                if let category {
                    try await store.updateCategory(category.id, payload: RemoteCategoryUpdatePayload(name: name, income: income, iconIdentifier: iconIdentifier, color: color))
                } else {
                    try await store.createCategory(RemoteCategoryCreatePayload(name: name, income: income, iconIdentifier: iconIdentifier, color: color))
                }
                dismiss()
            } catch {
                errorMessage = "Impossibile salvare la categoria. Riprova."
            }
        }
    }
}

private func decimalString(_ minor: Int64, exponent: Int) -> String {
    let number = NSDecimalNumber(mantissa: UInt64(abs(minor)), exponent: Int16(-exponent), isNegative: false)
    return number.stringValue
}

private func parseMinorUnits(_ text: String, exponent: Int) -> Int64? {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    guard let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), decimal > 0 else { return nil }
    let multiplier = NSDecimalNumber(value: Int64(pow(10.0, Double(exponent))))
    let scaled = NSDecimalNumber(decimal: decimal).multiplying(by: multiplier)
    let rounded = scaled.rounding(accordingToBehavior: nil)
    return rounded.int64Value
}

private func remoteCurrencySymbol(for currencyCode: String) -> String {
    Locale.current.localizedCurrencySymbol(forCurrencyCode: currencyCode) ?? currencyCode
}

private struct RemoteBalanceHeaderMetrics: Equatable {
    let minY: CGFloat
    let height: CGFloat
}

private struct RemoteBalanceHeaderMetricsKey: PreferenceKey {
    static var defaultValue = RemoteBalanceHeaderMetrics(minY: 0, height: 175)

    static func reduce(value: inout RemoteBalanceHeaderMetrics, nextValue: () -> RemoteBalanceHeaderMetrics) {
        value = nextValue()
    }
}

private struct RemoteScrollProgressModifier: ViewModifier {
    let onOffsetChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                geometry.contentOffset.y
            }, action: { _, offset in
                onOffsetChange(offset)
            })
        } else {
            content
        }
    }
}

private struct RemoteEditorRow<Content: View>: View {
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
