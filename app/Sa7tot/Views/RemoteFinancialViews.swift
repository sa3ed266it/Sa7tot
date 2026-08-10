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
    FinancialFormatting.currency(minorUnits: minor, currencyCode: currencyCode, exponent: exponent, showCents: showCents)
}

private func remoteAmountDigits(_ minor: Int64, currencyCode: String, exponent: Int, showCents: Bool = true) -> String {
    FinancialFormatting.digits(minorUnits: minor, currencyCode: currencyCode, exponent: exponent, showCents: showCents)
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
    return FinancialFormatting.date(date)
}

private func remoteTimeLabel(_ date: Date) -> String {
    return FinancialFormatting.time(date)
}

@available(iOS 26.0, *)
struct RemoteFinancialHomeView: View {
    @EnvironmentObject private var store: FinancialRemoteStore
    @EnvironmentObject private var authService: SupabaseAuthService

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
                .environmentObject(authService)
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
                Label(AppLocalization.key("movement.configurationTitle"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(AppLocalization.key("movement.configurationDescription"))
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                Text(AppLocalization.key("movement.configurationTitle"))
                    .font(.headline)
                Text(AppLocalization.key("movement.configurationDescription"))
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
        min(max(balanceCollapseProgress, 0), 1)
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
                    Label(AppLocalization.key("movement.empty.accountTitle"), systemImage: "building.columns")
                } description: {
                    Text(AppLocalization.key("movement.empty.accountDescription"))
                } actions: {
                    Button(AppLocalization.key("action.addAccount"), action: onAdd)
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
                collapseProgress: balanceCollapseProgress,
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
                    .scaleEffect(0.80 + (0.20 * balanceHandoff))
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
        .alert(AppLocalization.key("movement.deleteTitle"), isPresented: $isDeleteAlertPresented, presenting: deleteCandidate) { transaction in
            Button(AppLocalization.key("action.delete"), role: .destructive) {
                Task {
                    try? await store.deleteTransaction(transaction.id)
                }
            }
            Button(AppLocalization.key("action.cancel"), role: .cancel) {}
        } message: { _ in
            Text(AppLocalization.key("movement.deleteMessage"))
        }
        .alert(AppLocalization.key("common.error"), isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button(AppLocalization.key("action.retry")) { Task { await store.refresh() } }
            Button(AppLocalization.key("action.cancel"), role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(verbatim: store.errorMessage ?? AppLocalization.string("movement.loadError"))
        }
        .alert(AppLocalization.key("movement.deferredTitle"), isPresented: Binding(get: { store.deferredFeatureMessage != nil }, set: { if !$0 { store.deferredFeatureMessage = nil } })) {
            Button(AppLocalization.key("action.ok"), role: .cancel) { store.deferredFeatureMessage = nil }
        } message: {
            Text(verbatim: store.deferredFeatureMessage ?? AppLocalization.string("movement.deferredError"))
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
                    RemoteMovementRow(transaction: transaction, showCents: showCents) {
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
                        Text(AppLocalization.key("movement.incoming"))
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
                    RemoteMovementRow(upcoming: item, showCents: showCents)
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
                    .accessibilityLabel(AppLocalization.key("movement.removeFilter"))
                }
                .padding(4)
                .padding(.horizontal, 6)
                .background(Color.AppSecondarySurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Spacer()
            }

            switch store.filter {
            case .type:
                Picker(AppLocalization.key("common.type"), selection: $store.typeIsIncome) {
                    Text(AppLocalization.key("movement.expenses")).tag(false)
                    Text(AppLocalization.key("movement.incomes")).tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: store.typeIsIncome) { _ in store.setFilter(.type) }
            case .day:
                DatePicker(AppLocalization.key("filter.day"), selection: $store.selectedDay, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .onChange(of: store.selectedDay) { _ in store.setFilter(.day) }
            case .week:
                DatePicker(AppLocalization.key("filter.week"), selection: $store.selectedWeek, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .onChange(of: store.selectedWeek) { _ in store.setFilter(.week) }
            case .month:
                DatePicker(AppLocalization.key("filter.month"), selection: $store.selectedMonth, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .onChange(of: store.selectedMonth) { _ in store.setFilter(.month) }
            case .category:
                Picker(AppLocalization.key("common.category"), selection: Binding(get: { store.selectedCategoryID }, set: { store.selectedCategoryID = $0; store.setFilter(.category) })) {
                    Text(AppLocalization.key("category.all")).tag(UUID?.none)
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
    let collapseProgress: CGFloat
    let onFilter: (RemoteMovementFilter) -> Void
    let onTransfer: () -> Void

    func makeUIViewController(context: Context) -> RemoteFilterMenuViewController {
        RemoteFilterMenuViewController(
            filter: $filter,
            hideBalances: $hideBalances,
            selectedAccountID: selectedAccountID,
            collapseProgress: collapseProgress,
            onFilter: onFilter,
            onTransfer: onTransfer
        )
    }

    func updateUIViewController(_ viewController: RemoteFilterMenuViewController, context: Context) {
        viewController.filter = $filter
        viewController.hideBalances = $hideBalances
        viewController.selectedAccountID = selectedAccountID
        viewController.collapseProgress = collapseProgress
        viewController.onFilter = onFilter
        viewController.onTransfer = onTransfer
        viewController.installMenuIfNeeded()
        viewController.updateButtonVisibilities()
    }
}

private final class RemoteFilterMenuViewController: UIViewController {
    var filter: Binding<RemoteMovementFilter>
    var hideBalances: Binding<Bool>
    var selectedAccountID: UUID?
    var collapseProgress: CGFloat
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
        collapseProgress: CGFloat,
        onFilter: @escaping (RemoteMovementFilter) -> Void,
        onTransfer: @escaping () -> Void
    ) {
        self.filter = filter
        self.hideBalances = hideBalances
        self.selectedAccountID = selectedAccountID
        self.collapseProgress = collapseProgress
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
            filterButton.accessibilityLabel = AppLocalization.string("movement.filter")
            filterButton.accessibilityValue = filter.wrappedValue.title

            let privacyButton = UIBarButtonItem(
                image: UIImage(systemName: hideBalances.wrappedValue ? "eye.slash" : "eye"),
                style: .plain,
                target: self,
                action: #selector(toggleBalanceVisibility)
            )
            privacyButton.accessibilityLabel = AppLocalization.string(hideBalances.wrappedValue ? "movement.showBalance" : "movement.hideBalance")
            privacyButton.accessibilityValue = AppLocalization.string(hideBalances.wrappedValue ? "movement.balanceHidden" : "movement.balanceVisible")

            let transferButton = UIBarButtonItem(
                image: UIImage(systemName: "arrow.left.arrow.right"),
                style: .plain,
                target: self,
                action: #selector(openTransfer)
            )
            transferButton.accessibilityLabel = AppLocalization.string("action.addTransfer")
            transferButton.isEnabled = selectedAccountID != nil

            navigationItem.rightBarButtonItems = collapseProgress > 0.4 ? [privacyButton] : [filterButton, privacyButton]
            navigationItem.leftBarButtonItem = transferButton
            installedNavigationItem = navigationItem
            installedBarButtonItem = filterButton
            installedPrivacyButtonItem = privacyButton
            installedTransferButtonItem = transferButton
        } else {
            installedBarButtonItem?.menu = makeFilterMenu()
            installedBarButtonItem?.accessibilityValue = filter.wrappedValue.title
            installedPrivacyButtonItem?.image = UIImage(systemName: hideBalances.wrappedValue ? "eye.slash" : "eye")
            installedPrivacyButtonItem?.accessibilityLabel = AppLocalization.string(hideBalances.wrappedValue ? "movement.showBalance" : "movement.hideBalance")
            installedPrivacyButtonItem?.accessibilityValue = AppLocalization.string(hideBalances.wrappedValue ? "movement.balanceHidden" : "movement.balanceVisible")
            installedTransferButtonItem?.isEnabled = selectedAccountID != nil
        }
        updateButtonVisibilities()
    }

    func updateButtonVisibilities() {
        guard let navigationItem = installedNavigationItem else { return }
        guard let filterButton = installedBarButtonItem, let privacyButton = installedPrivacyButtonItem else { return }

        let currentlySingle = (navigationItem.rightBarButtonItems?.count ?? 0) == 1
        let shouldBeSingle = currentlySingle ? (collapseProgress > 0.28) : (collapseProgress > 0.45)
        let targetRightItems = shouldBeSingle ? [privacyButton] : [filterButton, privacyButton]

        if (navigationItem.rightBarButtonItems ?? []) != targetRightItems {
            navigationItem.setRightBarButtonItems(targetRightItems, animated: true)
        }
        installedTransferButtonItem?.isEnabled = selectedAccountID != nil
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
        return UIMenu(title: AppLocalization.string("movement.filter"), options: [.singleSelection], children: actions)
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
                .font(.system(size: 19, design: .rounded).weight(.medium))
                .foregroundStyle(Color.PrimaryText.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 8)

            if let snapshot {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(snapshot.balanceMinor >= 0 ? currencySymbol : "-\(currencySymbol)")
                        .font(.system(size: 34, design: .rounded))
                        .foregroundStyle(Color.SubtitleText)
                        .layoutPriority(1)
                    Text(remoteAmountDigits(abs(snapshot.balanceMinor), currencyCode: snapshot.currencyCode, exponent: snapshot.currencyExponent, showCents: showCents))
                        .font(RemoteClashDisplayFont.font(size: 84))
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
                        .font(.system(size: 24, design: .rounded).weight(.medium))
                        .minimumScaleFactor(0.5)
                        .monospacedDigit()
                        .foregroundStyle(Color.IncomeGreen)
                        .lineLimit(1)

                    DottedLine()
                        .stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                        .frame(width: 1.7, height: 15)
                        .foregroundStyle(Color.Outline)

                    Text("-\(remoteAmountDigits(store.summary.expensesMinor, currencyCode: snapshot.currencyCode, exponent: snapshot.currencyExponent, showCents: showCents))")
                        .font(.system(size: 24, design: .rounded).weight(.medium))
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
        .scaleEffect(1 - (0.35 * collapseProgress), anchor: .top)
        .offset(y: -12 * collapseProgress)
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
    let onDetail: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    init(transaction: RemoteTransactionDTO, showCents: Bool, onDetail: @escaping () -> Void, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.transaction = transaction
        self.upcoming = nil
        self.showCents = showCents
        self.onDetail = onDetail
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    init(upcoming: RemoteUpcomingItemDTO, showCents: Bool) {
        self.transaction = nil
        self.upcoming = upcoming
        self.showCents = showCents
        self.onDetail = {}
        self.onEdit = {}
        self.onDelete = {}
    }

    var body: some View {
        Button(action: onDetail) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: displayTitle)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.PrimaryText)
                        .lineLimit(1)
                    Text(verbatim: subtitle)
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
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let transaction {
                if transaction.kind != .transfer { Button(AppLocalization.key("action.edit"), action: onEdit) }
                Button(AppLocalization.key("action.delete"), role: .destructive, action: onDelete)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        iconContent
            .frame(width: 34, height: 34, alignment: .center)
    }

    @ViewBuilder
    private var iconContent: some View {
        if let transaction, transaction.kind == .transfer {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.PrimaryText)
        } else if let transaction, let serviceID = transaction.subscription?.serviceID,
                  let service = SubscriptionServiceCatalog.service(forID: serviceID) {
            SubscriptionLogoView(service: service, size: 34)
        } else if let transaction {
            CategoryLogIconView(
                iconIdentifier: transaction.category?.iconIdentifier ?? "sf:tag.fill",
                categoryName: transaction.category?.name,
                colour: transaction.category?.color ?? "#FFFFFF",
                future: false
            )
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
        }
    }

    private var subtitle: String {
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
            case let .recurrence(item): return item.category?.name ?? AppLocalization.string(item.transactionKind == .income ? "movement.income" : "movement.expense")
            }
        }
        guard let transaction else { return "" }
        return displayTitle(for: transaction)
    }

    private func displayTitle(for transaction: RemoteTransactionDTO) -> String {
        if transaction.kind == .transfer {
            return AppLocalization.string("movement.transfer")
        }
        if let serviceID = transaction.subscription?.serviceID,
           let service = SubscriptionServiceCatalog.service(forID: serviceID) {
            return service.displayName
        }
        if let categoryName = transaction.category?.name, !categoryName.isEmpty {
            return categoryName
        }
        return AppLocalization.string(transaction.kind == .income ? "movement.income" : "movement.expense")
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
                    VStack(spacing: 6) {
                        Text(headerOperationType)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.SubtitleText)
                            .frame(maxWidth: .infinity, alignment: .center)

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

                            Text("\(amountPrefix)\(currencySymbol)")
                                .font(.system(.headline, design: .rounded).weight(.medium))
                                .hidden()
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(AppLocalization.format("accessibility.amount", "\(amountPrefix)\(currencySymbol)\(amountDigits)"))
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)

                    VStack(spacing: 0) {
                        if let category = transaction.category, transaction.kind != .transfer {
                            categoryDetailRow(label: AppLocalization.string("common.category"), category: category)
                        }
                        if transaction.kind != .transfer, let accountName {
                            accountDetailRow(label: AppLocalization.string("common.account"), name: accountName, account: account)
                        }
                        if let transfer = transaction.transfer {
                            accountDetailRow(label: AppLocalization.string("transfer.from"), name: transfer.sourceAccountName, account: sourceAccount)
                            accountDetailRow(label: AppLocalization.string("transfer.to"), name: transfer.destinationAccountName, account: destinationAccount)
                        }
                        detailRow(label: AppLocalization.string("common.date"), value: remoteDateLabel(transaction.localDay))
                        detailRow(label: AppLocalization.string("common.time"), value: remoteTimeLabel(transaction.occurredAt))
                    }

                    if let displayNote {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppLocalization.key("common.note"))
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
                    Button(AppLocalization.key("action.close")) { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var headerOperationType: String {
        if transaction.kind == .transfer {
            return AppLocalization.string("movement.transfer")
        }
        if transaction.subscription != nil {
            return AppLocalization.string("subscription.detail")
        }
        if transaction.kind == .income {
            return AppLocalization.string("movement.income")
        }
        return AppLocalization.string("movement.expense")
    }

    private var amountDigits: String {
        FinancialFormatting.digits(
            minorUnits: displayedAmount ?? 0,
            currencyCode: transaction.currencyCode,
            exponent: transaction.currencyExponent,
            showCents: showCents
        )
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

    private var account: RemoteAccountDTO? {
        store.accounts.first(where: { $0.id == transaction.accountID })
    }

    private var sourceAccount: RemoteAccountDTO? {
        store.accounts.first(where: { $0.id == transaction.accountID })
    }

    private var destinationAccount: RemoteAccountDTO? {
        guard let destinationID = transaction.destinationAccountID else { return nil }
        return store.accounts.first(where: { $0.id == destinationID })
    }

    private var displayTitle: String {
        if transaction.kind == .transfer {
            return AppLocalization.string("movement.transfer")
        }
        if let serviceID = transaction.subscription?.serviceID,
           let service = SubscriptionServiceCatalog.service(forID: serviceID) {
            return service.displayName
        }
        if let categoryName = transaction.category?.name, !categoryName.isEmpty {
            return categoryName
        }
        return AppLocalization.string(transaction.kind == .income ? "movement.income" : "movement.expense")
    }

    private var displayNote: String? {
        guard let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return nil }
        guard transaction.subscription == nil else {
            let serviceID = transaction.subscription?.serviceID ?? ""
            return SubscriptionDisplayIdentity.normalized(note) == SubscriptionDisplayIdentity.normalized(serviceID) ? nil : note
        }
        return note
    }

    private func categoryDetailRow(label: String, category: RemoteCategoryBriefDTO) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .foregroundStyle(Color.SubtitleText)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                CategoryIconView(
                    descriptor: CategoryIconPresentation.descriptor(for: category.iconIdentifier),
                    role: .listRow,
                    tint: accountDisplayColor(category.color),
                    accessibilityLabel: ""
                )
                .accessibilityHidden(true)

                Text(category.name)
                    .foregroundStyle(Color.PrimaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }

    private func accountDetailRow(label: String, name: String, account: RemoteAccountDTO?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .foregroundStyle(Color.SubtitleText)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                if let account {
                    Image(systemName: Sa7totSymbolResolver.resolved(account.iconName, fallback: "building.columns.fill"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: account.color))
                        .accessibilityHidden(true)
                }

                Text(name)
                    .foregroundStyle(Color.PrimaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
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
    var title: String {
        switch self {
        case .expense: return AppLocalization.string("movement.expense")
        case .income: return AppLocalization.string("movement.income")
        case .subscription: return AppLocalization.string("movement.subscription")
        }
    }
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
    @EnvironmentObject private var appToastCoordinator: AppToastCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var amountFocused: Bool
    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) private var showCents = true

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
    @State private var showingNewCategory = false
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
            .alert(AppLocalization.key("common.error"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(AppLocalization.key("action.ok"), role: .cancel) { errorMessage = nil }
            } message: { Text(verbatim: errorMessage ?? AppLocalization.string("transaction.saveError")) }
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                typeSelector
                amountSection
                modeSpecificContent
                    .id(mode)
                    .transition(modeContentTransition)
                    .animation(modeAnimation, value: mode)
            }
            .padding(.horizontal, 17)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppLocalization.key("action.cancel")) { dismiss() }
                    .opacity(isSaving ? 0 : 1)
                    .disabled(isSaving)
                    .accessibilityHidden(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Text(AppLocalization.key("action.save"))
                    }
                }
                .frame(minWidth: 44)
                .disabled(isSaving || !canSave)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AppLocalization.key("action.finish")) {
                    amountFocused = false
                    UIApplication.shared.endEditing()
                }
                .accessibilityLabel(AppLocalization.key("accessibility.finishAmount"))
            }
        }
        .sheet(isPresented: $showNoteSheet, onDismiss: { noteDraft = note }) {
            RemoteTransactionNoteSheet(note: $note, draft: $noteDraft, isPresented: $showNoteSheet)
        }
        .sheet(isPresented: $showingNewCategory) {
            RemoteCategoryEditorView(
                category: nil,
                initialIncome: mode == .income,
                onCreated: { createdCategory in
                    if createdCategory.income == (mode == .income) {
                        categoryID = createdCategory.id
                    }
                }
            )
            .environmentObject(store)
            .environmentObject(appToastCoordinator)
        }
    }

    private var title: String {
        if isTransfer { return AppLocalization.string(isEditing ? "transfer.edit" : "action.addTransfer") }
        if mode == .subscription { return AppLocalization.string(isEditing ? "subscription.edit" : "subscription.new") }
        if isEditing { return AppLocalization.string("transaction.edit") }
        return AppLocalization.string("transaction.new")
    }

    @ViewBuilder private var typeSelector: some View {
        if isTransfer {
            Text(AppLocalization.key("movement.transfer"))
                .frame(maxWidth: .infinity)
                .accessibilityLabel(AppLocalization.key("accessibility.typeTransfer"))
        } else if isSubscription {
            Text(AppLocalization.key("movement.subscription"))
                .frame(maxWidth: .infinity)
                .accessibilityLabel(AppLocalization.key("accessibility.typeSubscription"))
        } else {
            Picker(AppLocalization.key("transaction.type"), selection: modeBinding) {
                Text(AppLocalization.key("movement.expense")).tag(RemoteTransactionEditorMode.expense)
                Text(AppLocalization.key("movement.income")).tag(RemoteTransactionEditorMode.income)
                if !isEditing { Text(AppLocalization.key("movement.subscription")).tag(RemoteTransactionEditorMode.subscription) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(AppLocalization.key("transaction.type"))
        }
    }

    @ViewBuilder private var modeSpecificContent: some View {
        if mode == .subscription {
            subscriptionContent
        } else {
            if !isTransfer { categoryCarousel }
            detailsSection
        }
    }

    private var modeBinding: Binding<RemoteTransactionEditorMode> {
        Binding(
            get: { mode },
            set: { newValue in
                withAnimation(modeAnimation) {
                    mode = newValue
                    categoryID = nil
                }
            }
        )
    }

    private var modeAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .easeInOut(duration: 0.25)
    }

    private var modeContentTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        return .asymmetric(
            insertion: .modifier(
                active: RemoteModeContentTransitionModifier(opacity: 0, blur: 4, horizontalOffset: 10),
                identity: RemoteModeContentTransitionModifier(opacity: 1, blur: 0, horizontalOffset: 0)
            ),
            removal: .modifier(
                active: RemoteModeContentTransitionModifier(opacity: 0, blur: 4, horizontalOffset: -10),
                identity: RemoteModeContentTransitionModifier(opacity: 1, blur: 0, horizontalOffset: 0)
            )
        )
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
                .modifier(RemoteAmountChangeAnimation(trigger: amountText, reduceMotion: reduceMotion))
                .accessibilityLabel(AppLocalization.key("common.amount"))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { amountFocused = true }
        .padding(.vertical, 4)
    }

    private var categoryCarousel: some View {
        Group {
            if filteredCategories.isEmpty {
                Button { showingNewCategory = true } label: {
                    Label(AppLocalization.key("action.addCategory"), systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 14)
                        .background(Color.AppSecondarySurface, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.key("action.addCategory"))
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
                                            tint: Color(hex: category.color),
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

                            Button { showingNewCategory = true } label: {
                                Label(AppLocalization.key("action.addCategory"), systemImage: "plus.circle.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .frame(minHeight: 44)
                                    .padding(.horizontal, 14)
                                    .background(Color.AppSecondarySurface, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AppLocalization.key("action.addCategory"))
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
                        Text(verbatim: subscriptionIsCustom && !subscriptionCustomName.isEmpty ? subscriptionCustomName : subscriptionService?.displayName ?? AppLocalization.string("subscription.chooseService"))
                            .foregroundStyle(subscriptionService == nil && !subscriptionIsCustom ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 48)
                }
                .buttonStyle(.plain)

                if subscriptionIsCustom {
                    TextField(AppLocalization.key("subscription.customName"), text: $subscriptionCustomName)
                        .textFieldStyle(.roundedBorder)
                }

                RemoteEditorRow(title: AppLocalization.string("common.frequency"), systemImage: "repeat") {
                    Picker(AppLocalization.key("common.frequency"), selection: $subscriptionCadence) {
                        Text(AppLocalization.key("subscription.weekly")).tag(SubscriptionCadence.weekly)
                        Text(AppLocalization.key("subscription.monthly")).tag(SubscriptionCadence.monthly)
                        Text(AppLocalization.key("subscription.yearly")).tag(SubscriptionCadence.yearly)
                    }
                    .labelsHidden()
                    .tint(.secondary)
                }
                RemoteEditorRow(title: AppLocalization.string("subscription.startDate"), systemImage: "calendar") {
                    DatePicker(AppLocalization.key("subscription.startDate"), selection: $subscriptionStartDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .environment(\.locale, .current)
                }
                RemoteEditorRow(title: AppLocalization.string("common.account"), systemImage: "building.columns.fill") {
                    RemoteAccountMenu(accounts: store.activeAccounts, selection: $accountID, singleLine: true)
                }
                noteRow
            }
        }
    }

    private var detailsSection: some View {
        GroupBox {
            VStack(spacing: 10) {
                if !isTransfer {
                    dateTimeRow
                }
                if isTransfer {
                    RemoteEditorRow(title: AppLocalization.string("transfer.from"), systemImage: "arrow.up.right") {
                        RemoteAccountMenu(accounts: store.activeAccounts, selection: $sourceID, singleLine: true)
                    }
                    RemoteEditorRow(title: AppLocalization.string("transfer.to"), systemImage: "arrow.down.left") {
                        RemoteAccountMenu(accounts: destinationAccounts, selection: $destinationID, singleLine: true)
                    }
                } else {
                    RemoteEditorRow(title: AppLocalization.string("common.account"), systemImage: "building.columns.fill") {
                        RemoteAccountMenu(accounts: store.activeAccounts, selection: $accountID, singleLine: true)
                    }
                }
                noteRow
            }
        }
    }

    private var dateTimeRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                Text(AppLocalization.string("transaction.dateTime"))
                    .fixedSize(horizontal: true, vertical: false)
            }
                .font(.subheadline)
                .layoutPriority(1)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                DatePicker("", selection: $occurredAt, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .controlSize(.small)
                DatePicker("", selection: $occurredAt, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .controlSize(.small)
            }
            .environment(\.locale, .current)
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: 44)
    }

    private var recurrenceRow: some View {
        RemoteEditorRow(title: AppLocalization.string("transaction.repeat"), systemImage: "repeat") {
            Menu {
                recurrenceChoice(AppLocalization.string("transaction.repeatNever"), type: 0, coefficient: 1)
                recurrenceChoice(AppLocalization.string("transaction.everyDay"), type: 1, coefficient: 1)
                recurrenceChoice(AppLocalization.string("transaction.everyWeek"), type: 2, coefficient: 1)
                recurrenceChoice(AppLocalization.string("transaction.everyMonth"), type: 3, coefficient: 1)
                Divider()
                Button(AppLocalization.key("transaction.customRecurrence")) { store.deferredFeatureMessage = AppLocalization.string("recurrence.customUnavailable") }
            } label: {
                HStack(spacing: 5) {
                    Text(repeatSummary)
                        .foregroundStyle(repeatType == 0 ? .secondary : Color.IncomeGreen)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(AppLocalization.key("transaction.repeat"))
            .accessibilityValue(repeatSummary)
            .tint(.secondary)
        }
    }

    private var noteRow: some View {
        RemoteEditorRow(title: AppLocalization.string("common.note"), systemImage: "note.text") {
            HStack(spacing: 8) {
                if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Button(AppLocalization.key(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "action.add" : "action.edit")) {
                    noteDraft = note
                    showNoteSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(AppLocalization.key(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "note.add" : "note.edit"))
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
        case 1: return AppLocalization.string("transaction.everyDay")
        case 2: return AppLocalization.string("transaction.everyWeek")
        case 3: return AppLocalization.string("transaction.everyMonth")
        default: return AppLocalization.string("transaction.repeatNever")
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
        guard !isSaving else { return }
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
                errorMessage = AppLocalization.string("subscription.saveError")
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
                    let createdTransaction = try await store.createTransaction(RemoteTransactionCreatePayload(
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
                    if let createdTransaction {
                        let signedAmountMinor = mode == .expense
                            ? -abs(createdTransaction.amountMinor)
                            : abs(createdTransaction.amountMinor)
                        appToastCoordinator.show(
                            kind: mode == .expense ? .expenseAdded : .incomeAdded,
                            amount: remoteSignedAmount(
                                signedAmountMinor,
                                currencyCode: createdTransaction.currencyCode,
                                exponent: createdTransaction.currencyExponent,
                                showCents: showCents
                            )
                        )
                    }
                    dismiss()
                    isSaving = false
                    return
                }
                dismiss()
            } catch {
                errorMessage = AppLocalization.string("transaction.saveError")
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
                errorMessage = AppLocalization.string("transfer.saveError")
            }
            isSaving = false
        }
    }
}

@available(iOS 26.0, *)
private struct RemoteEditorSheetPresentation: ViewModifier {
    let compact: Bool

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
                .presentationDetents([.height(560), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(AnyShapeStyle(Color.AppPageBackground.opacity(0.14)))
        }
    }
}

private struct RemoteModeContentTransitionModifier: ViewModifier {
    let opacity: Double
    let blur: CGFloat
    let horizontalOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blur)
            .offset(x: horizontalOffset)
    }
}

@available(iOS 17.0, *)
private struct RemoteAmountChangeAnimation: ViewModifier {
    let trigger: String
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .contentTransition(.opacity)
            .phaseAnimator([1.0, 0.0, 1.0], trigger: trigger) { content, phase in
                content
                    .opacity(reduceMotion ? 1 : 0.35 + (phase * 0.65))
                    .blur(radius: reduceMotion ? 0 : (1 - phase) * 4)
                    .offset(y: reduceMotion ? 0 : (1 - phase) * 4)
            } animation: { _ in
                reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .easeOut(duration: 0.2)
            }
    }
}

@available(iOS 26.0, *)
private struct RemoteAccountMenu: View {
    let accounts: [RemoteAccountDTO]
    @Binding var selection: UUID?
    let singleLine: Bool

    init(accounts: [RemoteAccountDTO], selection: Binding<UUID?>, singleLine: Bool = false) {
        self.accounts = accounts
        self._selection = selection
        self.singleLine = singleLine
    }

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
            HStack(spacing: 8) {
                Image(systemName: Sa7totSymbolResolver.resolved(selectedAccount?.iconName ?? "building.columns.fill"))
                    .foregroundStyle(accountDisplayColor(selectedAccount?.color))
                Text(selectedAccount?.name ?? AppLocalization.string("action.select"))
                    .lineLimit(singleLine ? 1 : nil)
                    .truncationMode(.tail)
            }
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.PrimaryText)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: singleLine ? 190 : nil, alignment: .leading)
            .background(Color.AppSecondarySurface, in: RoundedRectangle(cornerRadius: 11.5, style: .continuous))
        }
        .accessibilityLabel(AppLocalization.format("accessibility.account", selectedAccount?.name ?? AppLocalization.string("action.select")))
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
                        Text(AppLocalization.key("note.addPlaceholder"))
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
                        .accessibilityLabel(AppLocalization.key("common.note"))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .navigationTitle(AppLocalization.key("common.note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.key("action.cancel")) { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.key("action.finish")) {
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

private func accountDisplayColor(_ hex: String?) -> Color {
    guard let hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines),
          !hex.isEmpty,
          hex != "#FFFFFF",
          hex.caseInsensitiveCompare("FFFFFF") != .orderedSame else {
        return .primary
    }
    return Color(hex: hex)
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
                ContentUnavailableView(AppLocalization.key("account.empty"), systemImage: "building.columns", description: Text(AppLocalization.key("account.emptyDescription")))
            } else {
                ForEach(store.accounts) { account in
                    Button { editingAccount = account } label: {
                            HStack(spacing: 12) {
                            Image(systemName: Sa7totSymbolResolver.resolved(account.iconName))
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(accountDisplayColor(account.color))
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.name)
                                Text(verbatim: account.isArchived ? AppLocalization.string("account.archived") : localizedAccountType(account.type))
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
                                    catch { errorMessage = AppLocalization.string("account.archiveError") }
                                }
                            } label: {
                                Label(AppLocalization.key("action.archive"), systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(AppLocalization.key("account.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewAccount = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(AppLocalization.key("account.new"))
            }
        }
        .sheet(isPresented: $showingNewAccount) {
            RemoteAccountEditorView(account: nil).environmentObject(store)
        }
        .sheet(item: $editingAccount) { account in
            RemoteAccountEditorView(account: account).environmentObject(store)
        }
        .alert(AppLocalization.key("common.error"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(AppLocalization.key("action.ok"), role: .cancel) {}
        } message: { Text(verbatim: errorMessage ?? AppLocalization.string("account.editError")) }
        .task { await store.bootstrapIfNeeded() }
    }
}

private struct RemoteAccountIconOption: Identifiable, Hashable {
    let symbolName: String
    let titleKey: String

    var id: String { symbolName }
}

private enum RemoteAccountIconCatalog {
    static let all: [RemoteAccountIconOption] = [
        RemoteAccountIconOption(symbolName: "building.columns.fill", titleKey: "account.typeBank"),
        RemoteAccountIconOption(symbolName: "building.columns", titleKey: "account.typeBank"),
        RemoteAccountIconOption(symbolName: "banknote.fill", titleKey: "account.typeCash"),
        RemoteAccountIconOption(symbolName: "eurosign.circle.fill", titleKey: "account.typeCash"),
        RemoteAccountIconOption(symbolName: "creditcard.fill", titleKey: "account.typeCard"),
        RemoteAccountIconOption(symbolName: "wallet.bifold.fill", titleKey: "account.typeCash"),
        RemoteAccountIconOption(symbolName: "chart.line.uptrend.xyaxis", titleKey: "account.typeSavings"),
        RemoteAccountIconOption(symbolName: "house.fill", titleKey: "account.iconPicker"),
        RemoteAccountIconOption(symbolName: "briefcase.fill", titleKey: "account.iconPicker"),
        RemoteAccountIconOption(symbolName: "airplane", titleKey: "account.iconPicker"),
        RemoteAccountIconOption(symbolName: "ellipsis.circle.fill", titleKey: "account.typeOther")
    ].filter { UIImage(systemName: $0.symbolName) != nil }
}

private struct RemoteAccountIconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(RemoteAccountIconCatalog.all) { option in
                    Button {
                        selection = option.symbolName
                        dismiss()
                    } label: {
                        Image(systemName: option.symbolName)
                            .font(.system(size: 23, weight: .semibold))
                            .frame(width: 50, height: 50)
                            .foregroundStyle(Color.PrimaryText)
                            .background(Color.AppSecondarySurface, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(selection == option.symbolName ? Color.accentColor : .clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLocalization.key(option.titleKey))
                    .accessibilityAddTraits(selection == option.symbolName ? .isSelected : [])
                }
            }
            .padding(20)
        }
        .background(Color.AppPageBackground)
        .navigationTitle(AppLocalization.key("account.iconPicker"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppLocalization.key("action.cancel")) { dismiss() }
            }
        }
    }
}

private enum RemoteAccountTypeOption: String, CaseIterable, Identifiable {
    case cash
    case bank
    case card
    case savings
    case other

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .cash: return "account.typeCash"
        case .bank: return "account.typeBank"
        case .card: return "account.typeCard"
        case .savings: return "account.typeSavings"
        case .other: return "account.typeOther"
        }
    }
}

@available(iOS 26.0, *)
struct RemoteAccountEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinancialRemoteStore
    @EnvironmentObject private var appToastCoordinator: AppToastCoordinator
    let account: RemoteAccountDTO?

    @State private var name: String
    @State private var type: String
    @State private var currencyCode: String
    @State private var openingBalance: String
    @State private var iconName: String
    @State private var color: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var showingIconPicker = false

    init(account: RemoteAccountDTO?) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? "other")
        _currencyCode = State(initialValue: account?.currencyCode ?? "EUR")
        _openingBalance = State(initialValue: account.map { remoteAccountDecimalString($0.openingBalanceMinor, exponent: $0.currencyExponent) } ?? remoteAccountDecimalString(0, exponent: 2))
        let storedIcon = account?.iconName ?? "building.columns.fill"
        _iconName = State(initialValue: RemoteAccountIconCatalog.all.contains(where: { $0.symbolName == storedIcon }) ? storedIcon : "building.columns.fill")
        _color = State(initialValue: account?.color ?? "#5E7CE2")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.key("account.information")) {
                    TextField(AppLocalization.key("common.name"), text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    Picker(AppLocalization.key("common.type"), selection: $type) {
                        ForEach(RemoteAccountTypeOption.allCases) { option in
                            Text(AppLocalization.key(option.titleKey)).tag(option.rawValue)
                        }
                    }
                }

                Section(AppLocalization.key("account.balance")) {
                    HStack {
                        Text(AppLocalization.key("account.initialBalance"))
                        Spacer(minLength: 12)
                        Text(remoteCurrencySymbol(for: currencyCode))
                            .foregroundStyle(.secondary)
                        TextField("0,00", text: $openingBalance)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 100)
                            .monospacedDigit()
                            .accessibilityLabel(AppLocalization.key("account.initialBalance"))
                    }
                    Picker(AppLocalization.key("common.currency"), selection: $currencyCode) {
                        ForEach(Currency.allCurrencies, id: \.code) { currency in
                            Text("\(currency.code) — \(currency.name)").tag(currency.code)
                        }
                    }
                }

                Section(AppLocalization.key("account.appearance")) {
                    Button {
                        showingIconPicker = true
                    } label: {
                        HStack {
                            Text(AppLocalization.key("account.iconPicker"))
                            Spacer()
                            Image(systemName: Sa7totSymbolResolver.resolved(iconName))
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.PrimaryText)
                                .frame(width: 44, height: 44)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLocalization.key("account.iconPicker"))

                    ColorPicker(AppLocalization.key("common.color"), selection: colorBinding, supportsOpacity: false)
                }

                Section(AppLocalization.key("account.preview")) {
                    HStack(spacing: 12) {
                        Image(systemName: Sa7totSymbolResolver.resolved(iconName))
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(selectedColor)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: trimmedName.isEmpty ? AppLocalization.string("account.new") : trimmedName)
                                .font(.headline)
                            Text(remoteAmount(parsedOpeningBalance ?? 0, currencyCode: currencyCode, exponent: 2))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(AppLocalization.key("account.preview"))
                }
            }
            .navigationTitle(AppLocalization.key(account == nil ? "account.new" : "account.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.key("action.cancel")) { dismiss() }
                        .opacity(isSaving ? 0 : 1)
                        .disabled(isSaving)
                        .accessibilityHidden(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSaving {
                            ProgressView().controlSize(.regular)
                        } else {
                            Text(AppLocalization.key("action.save"))
                        }
                    }
                    .frame(minWidth: 44)
                    .disabled(isSaving || !isValid)
                }
            }
            .alert(AppLocalization.key("common.error"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(AppLocalization.key("action.ok"), role: .cancel) {}
            } message: { Text(verbatim: errorMessage ?? AppLocalization.string("account.saveError")) }
        }
        .sheet(isPresented: $showingIconPicker) {
            NavigationStack {
                RemoteAccountIconPickerView(selection: $iconName)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedOpeningBalance: Int64? {
        parseRemoteAccountMinorUnits(openingBalance, exponent: 2)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && parsedOpeningBalance != nil && Currency.currencyCodes.contains(currencyCode.uppercased())
    }

    private var selectedColor: Color {
        Color(hex: color)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { selectedColor },
            set: { color = $0.toHex() ?? color }
        )
    }

    private func save() {
        guard !isSaving, isValid, let amount = parsedOpeningBalance else { return }
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCurrency.count == 3 else {
            errorMessage = AppLocalization.string("account.validationError")
            return
        }
        isSaving = true
        Task {
            do {
                if let account {
                    try await store.updateAccount(account.id, payload: RemoteAccountUpdatePayload(name: trimmedName, type: type, openingBalanceMinor: amount, iconName: iconName, color: color))
                } else {
                    try await store.createAccount(RemoteAccountCreatePayload(name: trimmedName, type: type, currencyCode: normalizedCurrency, currencyExponent: 2, openingBalanceMinor: amount, iconName: iconName, color: color))
                }
                let shouldShowSuccessToast = account == nil
                dismiss()
                if shouldShowSuccessToast {
                    let toastCoordinator = appToastCoordinator
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        toastCoordinator.show(kind: .accountAdded)
                    }
                }
            } catch {
                errorMessage = AppLocalization.string("account.saveError")
            }
            isSaving = false
        }
    }
}

@available(iOS 26.0, *)
struct RemoteCategoryListView: View {
    private enum CategoryFilter: Hashable {
        case expense
        case income

        var isIncome: Bool {
            self == .income
        }

        var emptyStateKey: String {
            self == .income ? "category.emptyIncomes" : "category.emptyExpenses"
        }
    }

    @EnvironmentObject private var store: FinancialRemoteStore
    @State private var selectedFilter: CategoryFilter = .expense
    @State private var showingNewCategory = false
    @State private var editingCategory: RemoteCategoryDTO?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker(AppLocalization.key("category.filter"), selection: $selectedFilter) {
                Text(AppLocalization.key("category.expenses")).tag(CategoryFilter.expense)
                Text(AppLocalization.key("category.incomes")).tag(CategoryFilter.income)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            List {
                Section {
                    if filteredCategories.isEmpty {
                        Text(AppLocalization.key(selectedFilter.emptyStateKey))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                            .multilineTextAlignment(.center)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(filteredCategories) { category in
                            Button { editingCategory = category } label: {
                                HStack(spacing: 12) {
                                    CategoryIconView(
                                        descriptor: CategoryIconPresentation.descriptor(for: category.iconIdentifier),
                                        role: .category,
                                        tint: Color(hex: category.color),
                                        accessibilityLabel: category.name
                                    )
                                    .frame(width: 44, height: 44)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(category.name)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(AppLocalization.key(category.income ? "category.income" : "category.expense"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task {
                                        do { try await store.deleteCategory(category.id) }
                                        catch { errorMessage = AppLocalization.string("category.deleteError") }
                                    }
                                } label: {
                                    Label(AppLocalization.key("action.delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle(AppLocalization.key("category.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewCategory = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(AppLocalization.key("category.new"))
            }
        }
        .sheet(isPresented: $showingNewCategory) {
            RemoteCategoryEditorView(category: nil, initialIncome: selectedFilter.isIncome)
                .environmentObject(store)
        }
        .sheet(item: $editingCategory) { category in RemoteCategoryEditorView(category: category).environmentObject(store) }
        .alert(AppLocalization.key("common.error"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button(AppLocalization.key("action.ok"), role: .cancel) {} } message: { Text(verbatim: errorMessage ?? AppLocalization.string("category.editError")) }
        .task { await store.bootstrapIfNeeded() }
        .overlay {
            GeometryReader { proxy in
                AppToastView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, max(proxy.safeAreaInsets.top - proxy.frame(in: .global).minY, 0) + 7)
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
                    .zIndex(1000)
            }
        }
    }

    private func categoryTileColor(for category: RemoteCategoryDTO) -> Color {
        Color(hex: category.color)
    }

    private var filteredCategories: [RemoteCategoryDTO] {
        store.categories.filter { $0.income == selectedFilter.isIncome }
    }
}

@available(iOS 26.0, *)
struct RemoteCategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinancialRemoteStore
    @EnvironmentObject private var appToastCoordinator: AppToastCoordinator
    let category: RemoteCategoryDTO?
    var onCreated: ((RemoteCategoryDTO) -> Void)? = nil
    @State private var name: String
    @State private var income: Bool
    @State private var selectedSymbol: String
    @State private var color: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool

    private let palette = [
        "#279AF4", "#EC7A58", "#A6678A", "#C56AF7", "#6E7BF1", "#F3BF56",
        "#ED80A2", "#F6D24A", "#E34D63", "#61C7FA", "#84B4EB", "#5FAF9F"
    ]

    init(category: RemoteCategoryDTO?, initialIncome: Bool? = nil) {
        self.init(category: category, initialIncome: initialIncome, onCreated: nil)
    }

    init(category: RemoteCategoryDTO?, initialIncome: Bool?, onCreated: ((RemoteCategoryDTO) -> Void)?) {
        self.category = category
        self.onCreated = onCreated
        _name = State(initialValue: category?.name ?? "")
        _income = State(initialValue: category?.income ?? initialIncome ?? false)
        let descriptor = CategoryIconPresentation.descriptor(for: category?.iconIdentifier)
        _selectedSymbol = State(initialValue: {
            if case .sfSymbol(let symbol) = descriptor { return symbol }
            return "tag.fill"
        }())
        _color = State(initialValue: category?.color ?? "#279AF4")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    categoryPreview
                    typePicker
                    nameField
                    iconPicker
                    colorPicker

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.AlertRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color.AppPageBackground)
            .navigationTitle(AppLocalization.key(category == nil ? "category.new" : "category.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.key("action.cancel")) { dismiss() }
                        .opacity(isSaving ? 0 : 1)
                        .disabled(isSaving)
                        .accessibilityHidden(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.regular)
                        } else {
                            Text(AppLocalization.key("action.save"))
                        }
                    }
                    .frame(minWidth: 44)
                    .disabled(isSaving || trimmedName.isEmpty)
                }
            }
            .alert(AppLocalization.key("common.error"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button(AppLocalization.key("action.ok"), role: .cancel) {} } message: { Text(verbatim: errorMessage ?? AppLocalization.string("category.saveError")) }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var categoryPreview: some View {
        HStack(spacing: 14) {
            CategoryIconView(descriptor: .sfSymbol(selectedSymbol), role: .category, tint: selectedColor)
                .font(.system(size: 28, weight: .semibold))
                .frame(width: 44, height: 44)

            Text(trimmedName.isEmpty ? AppLocalization.string("category.preview") : trimmedName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(trimmedName.isEmpty ? Color.SubtitleText : Color.PrimaryText)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityHidden(true)
    }

    private var typePicker: some View {
        Picker(AppLocalization.key("common.type"), selection: $income) {
            Text(AppLocalization.key("category.expense")).tag(false)
            Text(AppLocalization.key("category.income")).tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(AppLocalization.key("common.type"))
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.key("common.name"))
                .font(.headline)
            TextField(AppLocalization.key("category.namePlaceholder"), text: $name)
                .textInputAutocapitalization(.sentences)
                .focused($nameFocused)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.AppSecondarySurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.key("category.iconPicker"))
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(iconColumns.indices, id: \.self) { index in
                        VStack(spacing: 12) {
                            ForEach(iconColumns[index]) { option in
                                iconButton(for: option)
                            }
                        }
                    }
                }
            }
            .frame(height: 3 * 44 + 2 * 12)
        }
    }

    private var iconOptions: [CategoryIconOption] {
        CategoryIconCatalog.options(for: income ? .income : .expense)
    }

    private var iconColumns: [[CategoryIconOption]] {
        stride(from: 0, to: iconOptions.count, by: 3).map { start in
            Array(iconOptions.dropFirst(start).prefix(3))
        }
    }

    private func iconButton(for option: CategoryIconOption) -> some View {
        Button {
            selectedSymbol = option.symbolName
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            CategoryIconView(
                descriptor: .sfSymbol(option.symbolName),
                role: .category,
                tint: .primary,
                accessibilityLabel: option.title
            )
            .frame(width: 44, height: 44)
            .background(selectedSymbol == option.symbolName ? Color.AppSecondarySurface : .clear, in: Circle())
            .overlay {
                if selectedSymbol == option.symbolName {
                    Circle().stroke(Color.accentColor.opacity(0.65), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedSymbol == option.symbolName ? .isSelected : [])
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppLocalization.key("common.color"))
                    .font(.headline)
                Spacer()
                ColorPicker(AppLocalization.key("common.color"), selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 40, maximum: 48), spacing: 10)], spacing: 10) {
                ForEach(palette, id: \.self) { value in
                    Button {
                        color = value
                    } label: {
                        Circle()
                            .fill(Color(hex: value))
                            .frame(width: 40, height: 40)
                            .overlay {
                                if color.caseInsensitiveCompare(value) == .orderedSame {
                                    Circle().stroke(.primary, lineWidth: 2)
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.primary)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLocalization.key("common.color"))
                    .accessibilityAddTraits(color.caseInsensitiveCompare(value) == .orderedSame ? .isSelected : [])
                }
            }
        }
    }

    private var selectedColor: Color {
        Color(hex: color)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { selectedColor },
            set: { color = $0.toHex() ?? color }
        )
    }

    private func save() {
        guard !isSaving, !trimmedName.isEmpty else { return }
        isSaving = true
        Task {
            do {
                if let category {
                    try await store.updateCategory(category.id, payload: RemoteCategoryUpdatePayload(name: trimmedName, income: income, iconIdentifier: "sf:\(selectedSymbol)", color: color))
                } else {
                    let created = try await store.createCategory(RemoteCategoryCreatePayload(name: trimmedName, income: income, iconIdentifier: "sf:\(selectedSymbol)", color: color))
                    onCreated?(created)
                }
                let shouldShowSuccessToast = category == nil
                dismiss()
                if shouldShowSuccessToast {
                    let toastCoordinator = appToastCoordinator
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        toastCoordinator.show(kind: .categoryAdded)
                    }
                }
            } catch {
                errorMessage = AppLocalization.string("category.saveError")
            }
            isSaving = false
        }
    }
}

private func decimalString(_ minor: Int64, exponent: Int) -> String {
    let number = NSDecimalNumber(mantissa: UInt64(abs(minor)), exponent: Int16(-exponent), isNegative: false)
    return number.stringValue
}

private func remoteAccountDecimalString(_ minor: Int64, exponent: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = .current
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = exponent
    formatter.maximumFractionDigits = exponent
    let divisor = Decimal(Int64(pow(10.0, Double(exponent))))
    let value = Decimal(minor) / divisor
    return formatter.string(for: NSDecimalNumber(decimal: value)) ?? "0"
}

private func parseRemoteAccountMinorUnits(_ text: String, exponent: Int) -> Int64? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    var normalized = trimmed.replacingOccurrences(of: " ", with: "")
    if normalized.contains(",") {
        normalized = normalized.replacingOccurrences(of: ".", with: "")
        normalized = normalized.replacingOccurrences(of: ",", with: ".")
    }
    guard let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { return nil }

    let multiplier = NSDecimalNumber(value: Int64(pow(10.0, Double(exponent))))
    let scaled = NSDecimalNumber(decimal: decimal).multiplying(by: multiplier)
    return scaled.rounding(accordingToBehavior: nil).int64Value
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

private func localizedAccountType(_ type: String) -> String {
    switch type.lowercased() {
    case "other": return AppLocalization.string("account.typeOther")
    default: return type
    }
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
