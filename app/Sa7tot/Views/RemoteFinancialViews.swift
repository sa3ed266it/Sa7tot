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

private enum RemoteFilterMotion {
    static let chipSpring = Animation.spring(response: 0.32, dampingFraction: 0.84)
    static let navigatorFade = Animation.easeOut(duration: 0.18)
    static let datasetExitDuration: Double = 0.10
    static let datasetEnterDuration: Double = 0.15
    static let debugOffset: CGFloat = -7
    static let debugScale: CGFloat = 0.95
}

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

private struct RemoteSplitFinancialAmount: View {
    let minorUnits: Int64
    let currencyCode: String
    let exponent: Int
    let showCents: Bool
    let prefixFontSize: CGFloat
    let digitsFontSize: CGFloat
    let color: Color
    let minimumScaleFactor: CGFloat
    let zeroSign: String?
    var showSign: Bool = true

    private var sign: String {
        if minorUnits > 0 {
            return "+"
        } else if minorUnits < 0 {
            return "−"
        }
        return zeroSign ?? ""
    }

    private var digits: String {
        FinancialFormatting.digits(
            minorUnits: minorUnits,
            currencyCode: currencyCode,
            exponent: exponent,
            showCents: showCents
        )
    }

    private var prefixText: String {
        showSign ? "\(sign)\(remoteCurrencySymbol(for: currencyCode))" : remoteCurrencySymbol(for: currencyCode)
    }

    private var accessibilityText: String {
        "\(sign)\(remoteCurrencySymbol(for: currencyCode))\(digits)"
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(prefixText)
                .font(.custom("HelveticaNeue-Medium", size: prefixFontSize))
                .foregroundStyle(color)

            Text(digits)
                .font(.custom("HelveticaNeue-Medium", size: digitsFontSize))
                .foregroundStyle(color)
        }
            .lineLimit(1)
            .minimumScaleFactor(minimumScaleFactor)
            .allowsTightening(true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppLocalization.format("accessibility.amount", accessibilityText))
    }
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
                RemoteAccountEditorView(
                    account: nil,
                    defaultCurrencyCode: "EUR"
                )
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
    @EnvironmentObject private var appToastCoordinator: AppToastCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var visualAccountID: UUID?
    @State private var displayedAccountID: UUID?
    @State private var handoffOpacity: CGFloat = 1.0
    @State private var handoffXOffset: CGFloat = 0.0
    @State private var handoffGeneration = 0
    @State private var lastSwipeDirection: Int = 1 // +1 = forward/next, -1 = backward/prev
    @State private var isMonthPickerPresented = false
    @State private var periodContentOpacity = 1.0
    @State private var periodContentOffset: CGFloat = 0
    @State private var isPeriodTransitioning = false
    @State private var periodTransitionGeneration = 0
    @State private var presentedFilter: RemoteMovementFilter? = nil
    @State private var isFilterVisible = false

    private let compactBalanceHeaderHeight: CGFloat = 54

    private var balanceHandoff: CGFloat {
        min(max(balanceCollapseProgress, 0), 1)
    }

    private var visualBinding: Binding<UUID?> {
        Binding(
            get: { visualAccountID ?? store.selectedAccountID },
            set: { visualAccountID = $0 }
        )
    }

    private enum MovimentiContentState {
        case loading
        case inlineError(AppError)
        case emptyNoAccount
        case content
    }

    private var movimentiContentState: MovimentiContentState {
        if !hasUsableMovementRows && store.activeAccounts.isEmpty {
            if let error = store.bootstrapError {
                return .inlineError(error)
            } else if store.bootstrapStatus == .failed {
                return .inlineError(.connectionFailed)
            }
        }

        if shouldShowColdLoader {
            return .loading
        }

        if (store.bootstrapStatus == .ready || store.didBootstrap) && store.activeAccounts.isEmpty {
            return .emptyNoAccount
        }

        return .content
    }

    var body: some View {
        Group {
            switch movimentiContentState {
            case .loading:
                Sa7totLoader()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .inlineError(error):
                MovimentiInlineErrorState(error: error) {
                    Task { await store.bootstrapIfNeeded() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .emptyNoAccount:
                ContentUnavailableView {
                    Label(AppLocalization.key("movement.empty.accountTitle"), systemImage: "building.columns")
                } description: {
                    Text(AppLocalization.key("movement.empty.accountDescription"))
                } actions: {
                    Button(AppLocalization.key("action.addAccount"), action: onAdd)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .content:
                movementContent
            }
        }
        .animation(.easeInOut(duration: 0.22), value: shouldShowColdLoader)
        .background(Color.AppPageBackground)
        .background {
            RemoteNativeFilterMenuBridge(
                filter: $store.filter,
                selectedCategoryID: $store.selectedCategoryID,
                hideBalances: $hideBalances,
                selectedAccountID: store.selectedAccountID,
                categories: store.categories,
                collapseProgress: balanceCollapseProgress,
                onFilter: { filter in
                    transitionFilter(to: filter)
                },
                onCategory: { categoryID in
                    transitionFilter(to: .category, categoryID: categoryID)
                },
                onTransfer: onTransfer
            )
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let account = store.selectedAccount {
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
        .sheet(isPresented: $isMonthPickerPresented) {
            RemoteMonthYearPickerSheet(
                selectedMonth: store.selectedMonth,
                monthStartDay: store.profile?.monthStartDay ?? 1,
                timeZoneIdentifier: store.profile?.timezone ?? FinancialPeriodNavigator.fallbackTimeZone,
                onCommit: { selectedMonth in
                    selectMonthWithTransition(selectedMonth)
                }
            )
            .presentationDetents([.height(300)])
        }
        .alert(AppLocalization.key("movement.deleteTitle"), isPresented: $isDeleteAlertPresented, presenting: deleteCandidate) { transaction in
            Button(AppLocalization.key("action.delete"), role: .destructive) {
                Task {
                    do {
                        try await store.deleteTransaction(transaction.id)
                    } catch {
                        appToastCoordinator.showError(titleKey: "error.mutation.delete.title", error: AppError.from(error))
                    }
                }
            }
            Button(AppLocalization.key("action.cancel"), role: .cancel) {}
        } message: { _ in
            Text(AppLocalization.key("movement.deleteMessage"))
        }
        .alert(AppLocalization.key("movement.deferredTitle"), isPresented: Binding(get: { store.deferredFeatureMessage != nil }, set: { if !$0 { store.deferredFeatureMessage = nil } })) {
            Button(AppLocalization.key("action.ok"), role: .cancel) { store.deferredFeatureMessage = nil }
        } message: {
            Text(verbatim: store.deferredFeatureMessage ?? AppLocalization.string("movement.deferredError"))
        }
        .onAppear {
            if store.filter != .all {
                presentedFilter = store.filter
                isFilterVisible = true
            } else {
                presentedFilter = nil
                isFilterVisible = false
            }
        }
        .onChange(of: store.filter) { _, newFilter in
            if newFilter != .all && presentedFilter == nil {
                presentedFilter = newFilter
                isFilterVisible = true
            } else if newFilter == .all && presentedFilter != nil && !isPeriodTransitioning {
                presentedFilter = nil
                isFilterVisible = false
            }
        }
    }

    private var shouldShowColdLoader: Bool {
        realColdLoaderCondition
    }

    private var realColdLoaderCondition: Bool {
        store.isLoading && !hasUsableAccountHeaderContent && !hasUsableMovementRows
    }

    private var hasUsableAccountHeaderContent: Bool {
        !store.activeAccounts.isEmpty
    }

    private var hasUsableMovementRows: Bool {
        if store.filter == .upcoming {
            return !store.upcomingItems.isEmpty
        }

        let accountID = store.selectedAccount?.id
        let days = accountID.map { store.cachedDays(for: $0) } ?? store.days
        return !days.isEmpty
    }

    private var movementContent: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 0).id("remote-movements-top")

                            RemoteAccountPager(
                                visualAccountID: visualBinding,
                                hideBalances: hideBalances,
                                showCents: showCents,
                                collapseProgress: balanceCollapseProgress,
                                handoff: balanceHandoff,
                                onCommitAccount: { accountID in
                                    performAccountSwitchHandoff(to: accountID, proxy: proxy)
                                },
                                reduceMotion: reduceMotion
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

                            LazyVStack(spacing: 0) {
                                VStack(spacing: 0) {
                                    HStack {
                                        Text(AppLocalization.key("tab.movements"))
                                            .font(.system(size: 22, weight: .bold, design: .rounded))
                                            .foregroundStyle(Color.PrimaryText)

                                        Spacer()

                                        Menu {
                                            Section {
                                                Button(action: { transitionFilter(to: .day) }) {
                                                    Label(RemoteMovementFilter.day.title, systemImage: store.filter == .day ? "checkmark" : "")
                                                }
                                                Button(action: { transitionFilter(to: .week) }) {
                                                    Label(RemoteMovementFilter.week.title, systemImage: store.filter == .week ? "checkmark" : "")
                                                }
                                                Button(action: { transitionFilter(to: .month) }) {
                                                    Label(RemoteMovementFilter.month.title, systemImage: store.filter == .month ? "checkmark" : "")
                                                }
                                            }

                                            Menu {
                                                ForEach(store.categories.filter { $0.deletedAt == nil }) { category in
                                                    Button(action: { transitionFilter(to: .category, categoryID: category.id) }) {
                                                        Label(category.name, systemImage: (store.filter == .category && store.selectedCategoryID == category.id) ? "checkmark" : "")
                                                    }
                                                }
                                                Button(action: { transitionFilter(to: .subscription) }) {
                                                    Label(AppLocalization.string("subscription.title"), systemImage: store.filter == .subscription ? "checkmark" : "")
                                                }
                                            } label: {
                                                Label(AppLocalization.string("filter.category"), systemImage: (store.filter == .category || store.filter == .subscription) ? "checkmark" : "")
                                            }
                                        } label: {
                                            ZStack {
                                                Circle()
                                                    .fill(store.filter == .all ? Color.AppSecondarySurface.opacity(0.8) : Color.PrimaryText.opacity(0.20))
                                                    .frame(width: 36, height: 36)

                                                Image(systemName: "line.3.horizontal.decrease")
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(store.filter == .all ? Color.PrimaryText.opacity(0.8) : Color.PrimaryText)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(AppLocalization.key("movement.filter"))
                                        .accessibilityValue(store.filter == .all ? AppLocalization.string("movement.filter") : store.filter.title)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.top, 22)
                                    .padding(.bottom, 14)

                                    if let activeFilter = presentedFilter {
                                        VStack(spacing: 12) {
                                            HStack {
                                                Spacer()
                                                Button {
                                                    transitionFilter(to: .all)
                                                } label: {
                                                    HStack(spacing: 6) {
                                                        Text(activeFilterChipTitle(for: activeFilter))
                                                            .contentTransition(.opacity)
                                                        Image(systemName: "xmark")
                                                            .font(.system(size: 11, weight: .semibold))
                                                    }
                                                }
                                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                                .buttonStyle(.glass)
                                                .buttonBorderShape(.capsule)
                                                .controlSize(.small)
                                                .accessibilityLabel(AppLocalization.key("movement.removeFilter"))
                                                .accessibilityValue(activeFilterChipTitle(for: activeFilter))
                                                Spacer()
                                            }

                                            if activeFilter == .week {
                                                RemoteFinancialPeriodNavigator(
                                                    label: remoteWeekLabel,
                                                    previousAccessibilityLabel: AppLocalization.string("filter.previousWeek"),
                                                    nextAccessibilityLabel: AppLocalization.string("filter.nextWeek"),
                                                    onPrevious: { navigateWeek(by: -1) },
                                                    onNext: { navigateWeek(by: 1) },
                                                    isNavigationDisabled: isPeriodTransitioning,
                                                    contentOpacity: periodContentOpacity,
                                                    contentOffset: periodContentOffset
                                                )
                                            } else if activeFilter == .month {
                                                RemoteFinancialPeriodNavigator(
                                                    label: remoteMonthLabel,
                                                    previousAccessibilityLabel: AppLocalization.string("filter.previousMonth"),
                                                    nextAccessibilityLabel: AppLocalization.string("filter.nextMonth"),
                                                    onPrevious: { navigateMonth(by: -1) },
                                                    onNext: { navigateMonth(by: 1) },
                                                    onLabelTap: { if !isPeriodTransitioning { isMonthPickerPresented = true } },
                                                    isNavigationDisabled: isPeriodTransitioning,
                                                    contentOpacity: periodContentOpacity,
                                                    contentOffset: periodContentOffset
                                                )
                                            } else if activeFilter == .day {
                                                DatePicker(AppLocalization.key("filter.day"), selection: $store.selectedDay, displayedComponents: .date)
                                                    .datePickerStyle(.compact)
                                                    .onChange(of: store.selectedDay) { oldValue, newValue in
                                                        performSerialPeriodTransition(direction: newValue > oldValue ? .next : .previous) {
                                                            store.setDayFilter(previousDay: oldValue)
                                                        }
                                                    }
                                            } else if activeFilter == .type {
                                                Picker(AppLocalization.key("common.type"), selection: $store.typeIsIncome) {
                                                    Text(AppLocalization.key("movement.expenses")).tag(false)
                                                    Text(AppLocalization.key("movement.incomes")).tag(true)
                                                }
                                                .pickerStyle(.segmented)
                                                .onChange(of: store.typeIsIncome) { oldValue, _ in store.setTypeFilter(previousValue: oldValue) }
                                            }
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.bottom, 12)
                                        .opacity(isFilterVisible ? 1 : 0)
                                        .scaleEffect(isFilterVisible ? 1.0 : RemoteFilterMotion.debugScale)
                                        .offset(y: isFilterVisible ? 0 : RemoteFilterMotion.debugOffset)
                                        .transition(
                                            .asymmetric(
                                                insertion: reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)),
                                                removal: reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
                                            )
                                        )
                                    }

                                    remoteMovementContainer
                                        .opacity(periodContentOpacity)
                                        .offset(x: periodContentOffset)
                                        .padding(.bottom, 20)
                                }
                                .background {
                                    UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 28, bottomTrailingRadius: 28, topTrailingRadius: 28, style: .continuous)
                                        .fill(Color.AppSecondarySurface)
                                        .ignoresSafeArea(edges: .bottom)
                                }

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
                    .onChange(of: store.selectedAccountID) { newID in
                        visualAccountID = newID
                        if displayedAccountID == nil {
                            displayedAccountID = newID
                        }
                    }
                    .onAppear {
                        if visualAccountID == nil {
                            visualAccountID = store.selectedAccountID
                        }
                        if displayedAccountID == nil {
                            displayedAccountID = store.selectedAccountID
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPreferenceChange(RemoteBalanceHeaderMetricsKey.self) { metrics in
                if let minY = metrics.minY {
                    expandedBalanceHeaderHeight = metrics.height
                    let collapseDistance = max(1, metrics.height - compactBalanceHeaderHeight)
                    balanceCollapseProgress = min(max(-minY / collapseDistance, 0), 1)
                }
            }
        }
        .refreshable { await store.refresh() }
    }

    private var remoteMovementContainer: some View {
        remoteMovementList(for: displayedAccountID ?? store.selectedAccountID)
            .opacity(handoffOpacity)
            .offset(x: handoffXOffset)
    }

    private func performAccountSwitchHandoff(to targetAccountID: UUID, proxy: ScrollViewProxy) {
        guard targetAccountID != store.selectedAccountID else { return }

        // Determine direction from account index order
        let accounts = store.activeAccounts
        let oldIndex = accounts.firstIndex(where: { $0.id == store.selectedAccountID }) ?? 0
        let newIndex = accounts.firstIndex(where: { $0.id == targetAccountID }) ?? 0
        let direction: CGFloat = newIndex > oldIndex ? -1.0 : 1.0 // next = exit left, prev = exit right
        lastSwipeDirection = newIndex > oldIndex ? 1 : -1

        handoffGeneration += 1
        let currentGeneration = handoffGeneration

        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                store.selectAccount(targetAccountID)
                displayedAccountID = targetAccountID
                visualAccountID = targetAccountID
                handoffOpacity = 1.0
                handoffXOffset = 0.0
            }
            proxy.scrollTo("remote-movements-top", anchor: .top)
            balanceCollapseProgress = 0
            return
        }

        // Phase 1 — Outgoing: movements exit in swipe direction (~0.10s)
        withAnimation(.easeIn(duration: 0.10)) {
            handoffOpacity = 0.0
            handoffXOffset = direction * 11.0
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard handoffGeneration == currentGeneration else { return }

            // Midpoint: swap data while invisible, position at opposite entry side
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                store.selectAccount(targetAccountID)
                displayedAccountID = targetAccountID
                visualAccountID = targetAccountID
                handoffXOffset = -direction * 11.0 // enter from opposite side
            }

            proxy.scrollTo("remote-movements-top", anchor: .top)
            balanceCollapseProgress = 0

            // Phase 2 — Incoming: movements arrive from opposite direction (~0.15s)
            withAnimation(.easeOut(duration: 0.15)) {
                handoffOpacity = 1.0
                handoffXOffset = 0.0
            }
        }
    }

    @ViewBuilder
    private func remoteMovementList(for accountID: UUID?) -> some View {
        let currentAccountID = accountID ?? store.selectedAccountID
        let days = currentAccountID.map { store.cachedDays(for: $0) } ?? store.days

        Group {
            if store.filter == .upcoming {
                remoteUpcomingList
            } else if days.isEmpty && !store.isLoading {
                NoResultsView()
            } else {
                remoteHistoryList(for: days)
            }
        }
    }

    @ViewBuilder
    private func remoteHistoryList(for days: [RemoteMovementDayDTO]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(days, id: \.day) { day in
                Section {
                    ForEach(Array(day.movements.enumerated()), id: \.element.id) { index, transaction in
                        let categoryChanged = index > 0 && movementPresentationIdentity(transaction) != movementPresentationIdentity(day.movements[index - 1])

                        VStack(spacing: 0) {
                            if index > 0 {
                                Rectangle()
                                    .fill(Color.PrimaryText.opacity(0.06))
                                    .frame(height: 0.5)
                                    .padding(.leading, 68)
                                    .padding(.trailing, 20)
                            }

                            RemoteMovementRow(transaction: transaction, showCents: showCents) {
                                detail = transaction
                            } onEdit: {
                                guard transaction.allowsDirectMutation else { return }
                                editing = transaction
                            } onDelete: {
                                guard transaction.allowsDirectMutation else { return }
                                deleteCandidate = transaction
                                isDeleteAlertPresented = true
                            }
                            .padding(.top, categoryChanged ? 4 : 0)
                            .contentShape(Rectangle())
                            .modifier(MovementRecedingScrollEffect())
                            .onAppear { store.loadNextPageIfNeeded(after: transaction.id) }
                        }
                    }
                } header: {
                    RemoteMovementDayHeaderView(
                        day: day,
                        showCents: showCents,
                        currencyCode: store.selectedCurrencyCode,
                        currencyExponent: store.selectedCurrencyExponent
                    )
                }
                .padding(.bottom, 14)
            }

            if store.isLoadingNextPage {
                Sa7totLoader(size: .compact).padding(.vertical, 14)
            } else if let _ = store.paginationError {
                HStack(spacing: 8) {
                    Text(AppLocalization.key("movement.paginationError"))
                        .font(.caption)
                        .foregroundStyle(Color.SubtitleText)

                    Button {
                        Task { await store.retryNextPage() }
                    } label: {
                        Text(AppLocalization.key("action.retry"))
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.mini)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

struct MovimentiInlineErrorState: View {
    let error: AppError
    let retry: () -> Void

    @State private var isRetrying = false

    private var presentation: AppErrorPresentation {
        AppErrorPresentationPolicy.blockingPresentation(for: error)
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: presentation.iconName)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(Color.SubtitleText)
                .accessibilityHidden(true)

            Text(LocalizedStringKey(presentation.titleKey))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Color.PrimaryText)

            Text(LocalizedStringKey(presentation.messageKey))
                .font(.subheadline)
                .foregroundStyle(Color.SubtitleText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if #available(iOS 26.0, *) {
                Button {
                    handleRetry()
                } label: {
                    buttonLabel
                }
                .buttonStyle(.glass)
                .disabled(isRetrying)
                .padding(.top, 4)
            } else {
                Button {
                    handleRetry()
                } label: {
                    buttonLabel
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRetrying)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    private var buttonLabel: some View {
        HStack(spacing: 6) {
            if isRetrying {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            Text(LocalizedStringKey(presentation.primaryActionKey))
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 6)
    }

    private func handleRetry() {
        guard !isRetrying else { return }
        isRetrying = true
        retry()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isRetrying = false
        }
    }
}

    private func movementPresentationIdentity(_ transaction: RemoteTransactionDTO) -> String {
        if transaction.kind == .transfer {
            return "kind:transfer"
        }
        if transaction.subscription != nil {
            return "kind:subscription"
        }
        if let categoryID = transaction.category?.id {
            return "category:\(categoryID.uuidString)"
        }
        return "kind:\(transaction.kind.rawValue)"
    }

    @ViewBuilder
    private var remoteUpcomingList: some View {
        if store.upcomingItems.isEmpty && !store.isLoading {
            NoResultsView()
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
                        .modifier(MovementRecedingScrollEffect())
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

    private func activeFilterChipTitle(for filter: RemoteMovementFilter) -> String {
        if filter == .category, let categoryID = store.selectedCategoryID, let category = store.categories.first(where: { $0.id == categoryID }) {
            return category.name
        }
        return filter.title
    }

    private var remoteFilterHeader: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button {
                    cancelPeriodTransition()
                    store.setFilter(.all)
                } label: {
                    HStack(spacing: 6) {
                        Text(store.filter.title)
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityLabel(AppLocalization.key("movement.removeFilter"))
                .accessibilityValue(store.filter.title)
                Spacer()
            }

            switch store.filter {
            case .type:
                Picker(AppLocalization.key("common.type"), selection: $store.typeIsIncome) {
                    Text(AppLocalization.key("movement.expenses")).tag(false)
                    Text(AppLocalization.key("movement.incomes")).tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: store.typeIsIncome) { oldValue, _ in store.setTypeFilter(previousValue: oldValue) }
            case .day:
                DatePicker(AppLocalization.key("filter.day"), selection: $store.selectedDay, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .onChange(of: store.selectedDay) { oldValue, _ in store.setDayFilter(previousDay: oldValue) }
            case .week:
                RemoteFinancialPeriodNavigator(
                    label: remoteWeekLabel,
                    previousAccessibilityLabel: AppLocalization.string("filter.previousWeek"),
                    nextAccessibilityLabel: AppLocalization.string("filter.nextWeek"),
                    onPrevious: { navigateWeek(by: -1) },
                    onNext: { navigateWeek(by: 1) },
                    isNavigationDisabled: isPeriodTransitioning,
                    contentOpacity: periodContentOpacity,
                    contentOffset: periodContentOffset
                )
            case .month:
                RemoteFinancialPeriodNavigator(
                    label: remoteMonthLabel,
                    previousAccessibilityLabel: AppLocalization.string("filter.previousMonth"),
                    nextAccessibilityLabel: AppLocalization.string("filter.nextMonth"),
                    onPrevious: { navigateMonth(by: -1) },
                    onNext: { navigateMonth(by: 1) },
                    onLabelTap: { if !isPeriodTransitioning { isMonthPickerPresented = true } },
                    isNavigationDisabled: isPeriodTransitioning,
                    contentOpacity: periodContentOpacity,
                    contentOffset: periodContentOffset
                )
            case .category:
                Picker(AppLocalization.key("common.category"), selection: Binding(get: { store.selectedCategoryID }, set: { store.setCategoryFilter($0) })) {
                    Text(AppLocalization.key("category.all")).tag(UUID?.none)
                    ForEach(store.categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .pickerStyle(.menu)
            case .all, .subscription, .recurring, .upcoming:
                EmptyView()
            }
        }
        .padding(.horizontal, 25)
        .frame(height: 110, alignment: .top)
        .padding(.top, 10)
    }

    private var financialTimeZoneIdentifier: String {
        store.profile?.timezone ?? FinancialPeriodNavigator.fallbackTimeZone
    }

    private var remoteWeekLabel: String {
        let window = FinancialPeriodNavigator.weekWindow(
            for: store.selectedWeek,
            weekStartDay: store.profile?.weekStartDay ?? 1,
            timeZoneIdentifier: financialTimeZoneIdentifier
        )
        let formatter = DateIntervalFormatter()
        formatter.locale = .current
        formatter.calendar = FinancialPeriodNavigator.calendar(timeZoneIdentifier: financialTimeZoneIdentifier)
        formatter.dateTemplate = "dMMM yyyy"
        return formatter.string(from: window.start, to: window.end.addingTimeInterval(-1))
    }

    private var remoteMonthLabel: String {
        let calendar = FinancialPeriodNavigator.calendar(timeZoneIdentifier: financialTimeZoneIdentifier)
        let date = FinancialPeriodNavigator.financialMonthStart(
            for: store.selectedMonth,
            monthStartDay: store.profile?.monthStartDay ?? 1,
            timeZoneIdentifier: financialTimeZoneIdentifier
        )
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized(with: formatter.locale)
    }

    private var periodExitDuration: Double { 0.12 }
    private var periodEnterDuration: Double { reduceMotion ? 0.12 : 0.15 }

    private func navigateWeek(by offset: Int) {
        guard !isPeriodTransitioning else { return }
        performSerialPeriodTransition(direction: offset < 0 ? .previous : .next) {
            await store.moveWeekAndWait(by: offset)
        }
    }

    private func navigateMonth(by offset: Int) {
        guard !isPeriodTransitioning else { return }
        performSerialPeriodTransition(direction: offset < 0 ? .previous : .next) {
            await store.moveMonthAndWait(by: offset)
        }
    }

    private func selectMonthWithTransition(_ selectedMonth: Date) {
        let calendar = FinancialPeriodNavigator.calendar(timeZoneIdentifier: financialTimeZoneIdentifier)
        let currentMonth = FinancialPeriodNavigator.financialMonthStart(
            for: store.selectedMonth,
            monthStartDay: store.profile?.monthStartDay ?? 1,
            timeZoneIdentifier: financialTimeZoneIdentifier
        )
        let nextMonth = FinancialPeriodNavigator.financialMonthStart(
            for: selectedMonth,
            monthStartDay: store.profile?.monthStartDay ?? 1,
            timeZoneIdentifier: financialTimeZoneIdentifier
        )
        let currentComponents = calendar.dateComponents([.year, .month], from: currentMonth)
        let nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
        let currentIndex = (currentComponents.year ?? 0) * 12 + (currentComponents.month ?? 0)
        let nextIndex = (nextComponents.year ?? 0) * 12 + (nextComponents.month ?? 0)
        guard nextIndex != currentIndex, !isPeriodTransitioning else {
            if !isPeriodTransitioning {
                Task { await store.selectMonthAndWait(selectedMonth) }
            }
            return
        }

        performSerialPeriodTransition(direction: nextIndex > currentIndex ? .next : .previous) {
            await store.selectMonthAndWait(selectedMonth)
        }
    }

    private func performSerialPeriodTransition(
        direction: RemotePeriodTransitionDirection,
        commit: @escaping @MainActor () async -> Void
    ) {
        guard !isPeriodTransitioning else { return }

        isPeriodTransitioning = true
        periodTransitionGeneration += 1
        let generation = periodTransitionGeneration
        let exitOffset: CGFloat = reduceMotion ? 0 : (direction == .next ? -18 : 18)
        let enterOffset = -exitOffset

        withAnimation(.easeInOut(duration: periodExitDuration)) {
            periodContentOpacity = 0
            periodContentOffset = exitOffset
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(periodExitDuration * 1_000_000_000))
            guard generation == periodTransitionGeneration else { return }

            await commit()
            guard generation == periodTransitionGeneration else { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                periodContentOffset = enterOffset
                periodContentOpacity = 0
            }

            withAnimation(.easeInOut(duration: periodEnterDuration)) {
                periodContentOpacity = 1
                periodContentOffset = 0
            }

            try? await Task.sleep(nanoseconds: UInt64(periodEnterDuration * 1_000_000_000))
            guard generation == periodTransitionGeneration else { return }
            isPeriodTransitioning = false
        }
    }

    private func transitionFilter(to newFilter: RemoteMovementFilter, categoryID: UUID? = nil) {
        guard !isPeriodTransitioning else { return }

        if reduceMotion {
            cancelPeriodTransition()
            store.setFilter(newFilter)
            if let categoryID { store.setCategoryFilter(categoryID) }
            presentedFilter = (newFilter == .all ? nil : newFilter)
            isFilterVisible = (newFilter != .all)
            return
        }

        isPeriodTransitioning = true
        periodTransitionGeneration += 1
        let generation = periodTransitionGeneration

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            guard generation == periodTransitionGeneration else { return }

            if newFilter == .all {
                withAnimation(RemoteFilterMotion.chipSpring) {
                    isFilterVisible = false
                }

                withAnimation(.easeIn(duration: RemoteFilterMotion.datasetExitDuration)) {
                    periodContentOpacity = 0
                }

                try? await Task.sleep(nanoseconds: 220_000_000)
                guard generation == periodTransitionGeneration else { return }

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    store.setFilter(.all)
                    presentedFilter = nil
                    periodContentOffset = 0
                }

                withAnimation(.easeOut(duration: RemoteFilterMotion.datasetEnterDuration)) {
                    periodContentOpacity = 1
                }

                try? await Task.sleep(nanoseconds: 150_000_000)
                guard generation == periodTransitionGeneration else { return }
                isPeriodTransitioning = false
            } else if store.filter == .all {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    presentedFilter = newFilter
                    isFilterVisible = false
                }

                withAnimation(.easeIn(duration: RemoteFilterMotion.datasetExitDuration)) {
                    periodContentOpacity = 0
                }

                try? await Task.sleep(nanoseconds: 80_000_000)
                guard generation == periodTransitionGeneration else { return }

                withTransaction(transaction) {
                    store.setFilter(newFilter)
                    if let categoryID { store.setCategoryFilter(categoryID) }
                    periodContentOffset = 0
                }

                withAnimation(RemoteFilterMotion.chipSpring) {
                    isFilterVisible = true
                }

                withAnimation(.easeOut(duration: RemoteFilterMotion.datasetEnterDuration)) {
                    periodContentOpacity = 1
                }

                try? await Task.sleep(nanoseconds: 150_000_000)
                guard generation == periodTransitionGeneration else { return }
                isPeriodTransitioning = false
            } else {
                withAnimation(.easeIn(duration: RemoteFilterMotion.datasetExitDuration)) {
                    periodContentOpacity = 0
                }

                try? await Task.sleep(nanoseconds: 80_000_000)
                guard generation == periodTransitionGeneration else { return }

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    store.setFilter(newFilter)
                    if let categoryID { store.setCategoryFilter(categoryID) }
                    presentedFilter = newFilter
                    periodContentOffset = 0
                }

                withAnimation(RemoteFilterMotion.navigatorFade) {
                    isFilterVisible = true
                }

                withAnimation(.easeOut(duration: RemoteFilterMotion.datasetEnterDuration)) {
                    periodContentOpacity = 1
                }

                try? await Task.sleep(nanoseconds: 150_000_000)
                guard generation == periodTransitionGeneration else { return }
                isPeriodTransitioning = false
            }
        }
    }

    private func cancelPeriodTransition() {
        periodTransitionGeneration += 1
        isPeriodTransitioning = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            periodContentOpacity = 1
            periodContentOffset = 0
        }
    }
}

private enum RemotePeriodTransitionDirection {
    case previous
    case next
}

@available(iOS 26.0, *)
private struct RemoteFinancialPeriodNavigator: View {
    let label: String
    let previousAccessibilityLabel: String
    let nextAccessibilityLabel: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    var onLabelTap: (() -> Void)?
    let isNavigationDisabled: Bool
    let contentOpacity: Double
    let contentOffset: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .disabled(isNavigationDisabled)
            .accessibilityLabel(previousAccessibilityLabel)

            Group {
                if let onLabelTap {
                    Button(action: onLabelTap) {
                        periodLabel
                    }
                } else {
                    periodLabel
                }
            }
            .frame(maxWidth: .infinity)
            .opacity(contentOpacity)
            .offset(x: contentOffset)

            Button(action: onNext) {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .disabled(isNavigationDisabled)
            .accessibilityLabel(nextAccessibilityLabel)
        }
        .font(.system(.body, design: .rounded).weight(.medium))
        .foregroundStyle(Color.PrimaryText)
        .accessibilityElement(children: .contain)
    }

    private var periodLabel: some View {
        Text(label)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
    }
}

private struct RemoteMonthYearPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectedMonth: Date
    let monthStartDay: Int
    let timeZoneIdentifier: String
    let onCommit: (Date) -> Void

    @State private var draftMonth: Int
    @State private var draftYear: Int

    // Bounded to 2000...2100: broad enough for existing financial data without an unbounded wheel.
    private let years = Array(2000...2100)

    init(selectedMonth: Date, monthStartDay: Int, timeZoneIdentifier: String, onCommit: @escaping (Date) -> Void) {
        self.selectedMonth = selectedMonth
        self.monthStartDay = monthStartDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.onCommit = onCommit
        let components = FinancialPeriodNavigator.displayMonthComponents(
            for: selectedMonth,
            monthStartDay: monthStartDay,
            timeZoneIdentifier: timeZoneIdentifier
        )
        _draftMonth = State(initialValue: components.month ?? 1)
        _draftYear = State(initialValue: components.year ?? Calendar.current.component(.year, from: .now))
    }

    var body: some View {
        NavigationView {
            RemoteMonthYearWheelPicker(month: $draftMonth, year: $draftYear, years: years)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(AppLocalization.string("filter.selectMonth"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppLocalization.string("action.cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppLocalization.string("action.done")) {
                            let date = FinancialPeriodNavigator.monthStart(
                                forDisplayYear: draftYear,
                                month: draftMonth,
                                monthStartDay: monthStartDay,
                                timeZoneIdentifier: timeZoneIdentifier
                            )
                            onCommit(date)
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct RemoteMonthYearWheelPicker: UIViewRepresentable {
    @Binding var month: Int
    @Binding var year: Int
    let years: [Int]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.delegate = context.coordinator
        picker.dataSource = context.coordinator
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        picker.selectRow(max(0, min(month - 1, 11)), inComponent: 0, animated: false)
        if let yearIndex = years.firstIndex(of: year) {
            picker.selectRow(yearIndex, inComponent: 1, animated: false)
        }
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: RemoteMonthYearWheelPicker

        init(_ parent: RemoteMonthYearWheelPicker) {
            self.parent = parent
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            component == 0 ? 12 : parent.years.count
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            if component == 0 {
                let formatter = DateFormatter()
                formatter.locale = .current
                return formatter.monthSymbols[row]
            }
            return String(parent.years[row])
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            if component == 0 {
                parent.month = row + 1
            } else {
                parent.year = parent.years[row]
            }
        }
    }
}

private struct RemoteNativeFilterMenuBridge: UIViewControllerRepresentable {
    @Binding var filter: RemoteMovementFilter
    @Binding var selectedCategoryID: UUID?
    @Binding var hideBalances: Bool
    let selectedAccountID: UUID?
    let categories: [RemoteCategoryDTO]
    let collapseProgress: CGFloat
    let onFilter: (RemoteMovementFilter) -> Void
    let onCategory: (UUID?) -> Void
    let onTransfer: () -> Void

    func makeUIViewController(context: Context) -> RemoteFilterMenuViewController {
        RemoteFilterMenuViewController(
            filter: $filter,
            selectedCategoryID: $selectedCategoryID,
            hideBalances: $hideBalances,
            selectedAccountID: selectedAccountID,
            categories: categories,
            collapseProgress: collapseProgress,
            onFilter: onFilter,
            onCategory: onCategory,
            onTransfer: onTransfer
        )
    }

    func updateUIViewController(_ viewController: RemoteFilterMenuViewController, context: Context) {
        viewController.filter = $filter
        viewController.selectedCategoryID = $selectedCategoryID
        viewController.hideBalances = $hideBalances
        viewController.selectedAccountID = selectedAccountID
        viewController.categories = categories
        viewController.collapseProgress = collapseProgress
        viewController.onFilter = onFilter
        viewController.onCategory = onCategory
        viewController.onTransfer = onTransfer
        viewController.installMenuIfNeeded()
        viewController.updateButtonVisibilities()
    }
}

private final class RemoteFilterMenuViewController: UIViewController {
    var filter: Binding<RemoteMovementFilter>
    var selectedCategoryID: Binding<UUID?>
    var hideBalances: Binding<Bool>
    var selectedAccountID: UUID?
    var categories: [RemoteCategoryDTO]
    var collapseProgress: CGFloat
    var onFilter: (RemoteMovementFilter) -> Void
    var onCategory: (UUID?) -> Void
    var onTransfer: () -> Void

    private weak var installedNavigationItem: UINavigationItem?
    private weak var installedBarButtonItem: UIBarButtonItem?
    private weak var installedPrivacyButtonItem: UIBarButtonItem?
    private weak var installedTransferButtonItem: UIBarButtonItem?

    init(
        filter: Binding<RemoteMovementFilter>,
        selectedCategoryID: Binding<UUID?>,
        hideBalances: Binding<Bool>,
        selectedAccountID: UUID?,
        categories: [RemoteCategoryDTO],
        collapseProgress: CGFloat,
        onFilter: @escaping (RemoteMovementFilter) -> Void,
        onCategory: @escaping (UUID?) -> Void,
        onTransfer: @escaping () -> Void
    ) {
        self.filter = filter
        self.selectedCategoryID = selectedCategoryID
        self.hideBalances = hideBalances
        self.selectedAccountID = selectedAccountID
        self.categories = categories
        self.collapseProgress = collapseProgress
        self.onFilter = onFilter
        self.onCategory = onCategory
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
            let settingsButton = UIBarButtonItem(
                image: UIImage(systemName: "gearshape"),
                style: .plain,
                target: self,
                action: #selector(settingsNoOp)
            )
            settingsButton.accessibilityLabel = AppLocalization.string("settings.title")

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

            navigationItem.rightBarButtonItems = collapseProgress > 0.4 ? [privacyButton] : [settingsButton, privacyButton]
            navigationItem.leftBarButtonItem = transferButton
            installedNavigationItem = navigationItem
            installedBarButtonItem = settingsButton
            installedPrivacyButtonItem = privacyButton
            installedTransferButtonItem = transferButton
        } else {
            installedBarButtonItem?.image = UIImage(systemName: "gearshape")
            installedBarButtonItem?.accessibilityLabel = AppLocalization.string("settings.title")
            installedPrivacyButtonItem?.image = UIImage(systemName: hideBalances.wrappedValue ? "eye.slash" : "eye")
            installedPrivacyButtonItem?.accessibilityLabel = AppLocalization.string(hideBalances.wrappedValue ? "movement.showBalance" : "movement.hideBalance")
            installedPrivacyButtonItem?.accessibilityValue = AppLocalization.string(hideBalances.wrappedValue ? "movement.balanceHidden" : "movement.balanceVisible")
            installedTransferButtonItem?.isEnabled = selectedAccountID != nil
        }
        updateButtonVisibilities()
    }

    func updateButtonVisibilities() {
        guard let navigationItem = installedNavigationItem else { return }
        guard let settingsButton = installedBarButtonItem, let privacyButton = installedPrivacyButtonItem else { return }

        let currentlySingle = (navigationItem.rightBarButtonItems?.count ?? 0) == 1
        let shouldBeSingle = currentlySingle ? (collapseProgress > 0.28) : (collapseProgress > 0.45)
        let targetRightItems = shouldBeSingle ? [privacyButton] : [settingsButton, privacyButton]

        if (navigationItem.rightBarButtonItems ?? []) != targetRightItems {
            navigationItem.setRightBarButtonItems(targetRightItems, animated: true)
        }
        installedTransferButtonItem?.isEnabled = selectedAccountID != nil
    }

    @objc private func settingsNoOp() {}

    @objc private func openTransfer() {
        onTransfer()
    }

    @objc private func toggleBalanceVisibility() {
        hideBalances.wrappedValue.toggle()
        installMenuIfNeeded()
    }

    private func makeFilterMenu() -> UIMenu {
        let periodFilters: [RemoteMovementFilter] = [.day, .week, .month]
        var children: [UIMenuElement] = periodFilters.map { option in
            UIAction(
                title: option.title,
                state: option == filter.wrappedValue ? .on : .off
            ) { [weak self] _ in
                self?.onFilter(option)
            }
        }

        children.append(makeCategoryMenu())

        return UIMenu(title: AppLocalization.string("movement.filter"), options: [.singleSelection], children: children)
    }

    private func makeCategoryMenu() -> UIMenu {
        let categoryActions = categories
            .filter { $0.deletedAt == nil }
            .map { category in
                UIAction(
                    title: category.name,
                    image: CategoryIconPresentation.menuImage(for: category),
                    state: filter.wrappedValue == .category && selectedCategoryID.wrappedValue == category.id ? .on : .off
                ) { [weak self] _ in
                    self?.onCategory(category.id)
                }
            }

        let subscriptionAction = UIAction(
            title: AppLocalization.string("subscription.title"),
            image: UIImage(systemName: "repeat.circle"),
            state: filter.wrappedValue == .subscription ? .on : .off
        ) { [weak self] _ in
            self?.onFilter(.subscription)
        }

        let isCategoryOrSubActive = (filter.wrappedValue == .category || filter.wrappedValue == .subscription)
        return UIMenu(
            title: AppLocalization.string("filter.category"),
            image: isCategoryOrSubActive ? UIImage(systemName: "checkmark") : nil,
            options: [],
            children: categoryActions + [subscriptionAction]
        )
    }

    private var filterAccessibilityValue: String {
        filter.wrappedValue == .all
            ? AppLocalization.string("movement.filter")
            : filter.wrappedValue.title
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
    @Binding var visualAccountID: UUID?
    let hideBalances: Bool
    let showCents: Bool
    let collapseProgress: CGFloat
    let handoff: CGFloat
    let onCommitAccount: (UUID) -> Void
    let reduceMotion: Bool

    private var pageControlReservedSpace: CGFloat {
        store.activeAccounts.count > 1 ? 24 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(store.activeAccounts) { account in
                        RemoteAccountHeaderPage(
                            account: account,
                            hideBalances: hideBalances,
                            showCents: showCents,
                            collapseProgress: collapseProgress,
                            handoff: handoff
                        )
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition(.interactive) { content, phase in
                            let raw = min(1.0, max(0.0, abs(phase.value)))
                            let p = reduceMotion ? 0.0 : (raw * raw * (3.0 - 2.0 * raw))

                            // Shared-axis: outgoing exits in swipe direction, incoming enters from opposite
                            let axisX = phase.value < 0 ? (-16.0 * p) : (16.0 * p)

                            // Asymmetric opacity: stays mostly visible early, fades decisively late
                            let outOpacity = 1.0 - smoothstepRange(0.20, 0.85, p)

                            // Tiny scale focus cue
                            let scale = 1.0 - (0.015 * p)

                            return content
                                .offset(x: axisX)
                                .opacity(max(0.0, outOpacity))
                                .scaleEffect(scale)
                        }
                        .id(account.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visualAccountID)
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .idle, let settledID = visualAccountID {
                    onCommitAccount(settledID)
                }
            }

            if store.activeAccounts.count > 1 {
                HStack(spacing: 6) {
                    ForEach(store.activeAccounts) { account in
                        Circle()
                            .fill(account.id == (visualAccountID ?? store.selectedAccountID ?? store.activeAccounts.first?.id) ? Color.PrimaryText.opacity(0.85) : Color.PrimaryText.opacity(0.25))
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut(duration: 0.18), value: visualAccountID)
                    }
                }
                .frame(height: 24)
            }
        }
        .scaleEffect(1 - (0.35 * collapseProgress), anchor: .top)
        .offset(y: -12 * collapseProgress)
        .frame(height: 220 + pageControlReservedSpace)
    }

    /// Attempt a smoothstep between edge0 and edge1, clamped to [0,1]
    private func smoothstepRange(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }
}

@available(iOS 26.0, *)
private struct RemoteAccountHeaderPage: View {
    @EnvironmentObject private var store: FinancialRemoteStore
    let account: RemoteAccountDTO
    let hideBalances: Bool
    let showCents: Bool
    let collapseProgress: CGFloat
    let handoff: CGFloat

    private var snapshot: RemoteAccountSnapshotDTO? {
        store.cachedSnapshot(for: account.id)
    }

    private var summary: RemoteMovementSummaryDTO? {
        store.cachedSummary(for: account.id)
    }

    var body: some View {
        AccountCardPreviewView(
            name: account.name,
            type: account.type,
            currencyCode: snapshot?.currencyCode ?? account.currencyCode,
            balanceMinor: snapshot?.balanceMinor ?? account.openingBalanceMinor,
            iconName: account.iconName,
            colorHex: account.color,
            currencyExponent: snapshot?.currencyExponent ?? account.currencyExponent,
            incomeMinor: summary?.incomeMinor,
            expensesMinor: summary?.expensesMinor,
            hideBalances: hideBalances,
            showCents: showCents,
            handoff: handoff
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

@available(iOS 26.0, *)
private struct RemoteMovementDayHeaderView: View {
    let day: RemoteMovementDayDTO
    let showCents: Bool
    let currencyCode: String
    let currencyExponent: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(remoteDateLabel(day.day).uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(Color.SubtitleText)

                Spacer()

                RemoteSplitFinancialAmount(
                    minorUnits: day.subtotalMinor,
                    currencyCode: currencyCode,
                    exponent: currencyExponent,
                    showCents: showCents,
                    prefixFontSize: 13,
                    digitsFontSize: 16,
                    color: day.subtotalMinor < 0 ? Color.AlertRed : day.subtotalMinor > 0 ? Color.IncomeGreen : Color.SubtitleText,
                    minimumScaleFactor: 0.7,
                    zeroSign: nil,
                    showSign: false
                )
                .layoutPriority(1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Rectangle()
                .fill(Color.PrimaryText.opacity(0.14))
                .frame(height: 1.0)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
        }
        .background(Color.AppSecondarySurface)
        .zIndex(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
        if transaction != nil {
            NativeTransactionContextMenuRow(
                identifier: transaction?.id.uuidString ?? "",
                canEdit: allowsEdit,
                canDelete: allowsDelete,
                editTitle: AppLocalization.string("action.edit"),
                deleteTitle: AppLocalization.string("action.delete"),
                content: rowButton,
                onEdit: { if allowsEdit { onEdit() } },
                onDelete: { if allowsDelete { onDelete() } }
            )
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        } else {
            rowButton
        }
    }

    private var allowsEdit: Bool {
        guard let transaction else { return false }
        return transaction.allowsDirectMutation
    }

    private var allowsDelete: Bool {
        guard let transaction else { return false }
        return transaction.allowsDirectMutation
    }

    private var rowButton: some View {
        Button(action: onDetail) {
            rowContent
        }
        .buttonStyle(.plain)
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: displayTitle)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.PrimaryText)
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.SubtitleText.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let amount = effectiveAmount {
                RemoteSplitFinancialAmount(
                    minorUnits: amount,
                    currencyCode: amountCurrencyCode,
                    exponent: amountCurrencyExponent,
                    showCents: showCents,
                    prefixFontSize: 14,
                    digitsFontSize: 18,
                    color: amount < 0 ? Color.AlertRed : amount > 0 ? Color.IncomeGreen : Color.SubtitleText,
                    minimumScaleFactor: 0.7,
                    zeroSign: nil,
                    showSign: false
                )
                .layoutPriority(1)
                .frame(width: 110, alignment: .trailing)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
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
        } else if let transaction, let subscription = transaction.subscription {
            SubscriptionLogoView(
                service: SubscriptionServiceCatalog.service(forID: subscription.serviceID),
                size: 34
            )
        } else if let transaction {
            categoryIconContent
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
            categoryIconContent
        }
    }

    @ViewBuilder
    private var categoryIconContent: some View {
        let identifier = transaction?.category?.iconIdentifier ?? upcomingCategory?.iconIdentifier ?? "sf:clock.arrow.circlepath"
        let categoryName = transaction?.category?.name ?? upcomingCategory?.name
        let colour = transaction?.category?.color ?? upcomingCategory?.color ?? "#FFFFFF"

        switch CategoryIconPresentation.descriptor(for: identifier) {
        case .sfSymbol(let symbol):
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(categoryIconTint(for: colour))
                .opacity(upcoming != nil ? 0.6 : 1)
                .accessibilityLabel(categoryName ?? AppLocalization.string("subscription.other"))
        case .asset, .appLogo:
            CategoryLogIconView(
                iconIdentifier: identifier,
                categoryName: categoryName,
                colour: colour,
                future: upcoming != nil
            )
            .frame(width: 16, height: 16)
        }
    }

    private func categoryIconTint(for colour: String) -> Color {
        let trimmed = colour.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "#FFFFFF" || trimmed.caseInsensitiveCompare("FFFFFF") == .orderedSame {
            return .primary
        }
        return Color(hex: trimmed)
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
        if transaction.subscription != nil {
            return AppLocalization.string("subscription.detail")
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
                        if transaction.kind == .transfer {
                            ZStack {
                                Circle()
                                    .fill(Color.AppSecondarySurface)
                                    .frame(width: 56, height: 56)
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.PrimaryText)
                            }
                            .padding(.bottom, 2)
                        } else if let subscription = transaction.subscription {
                            SubscriptionLogoView(
                                service: SubscriptionServiceCatalog.service(forID: subscription.serviceID),
                                size: 56
                            )
                            .padding(.bottom, 2)

                            Text(SubscriptionDisplayIdentity.serviceName(for: subscription))
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color.PrimaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .allowsTightening(true)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }

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
        if let subscription = transaction.subscription {
            if SubscriptionDisplayIdentity.isAutoGeneratedServiceNote(note, subscription: subscription) {
                return nil
            }
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

            Text(name)
                .foregroundStyle(Color.PrimaryText)
                .lineLimit(1)
                .truncationMode(.tail)
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
        if let transaction, transaction.kind == .transfer {
            RemoteTransferEditorView(transferTransaction: transaction)
        } else {
            RemoteMovementEditorSurface(kind: .transaction(transaction), initialAccountID: initialAccountID)
        }
    }
}

@available(iOS 26.0, *)
struct RemoteTransferEditorView: View {
    let transferTransaction: RemoteTransactionDTO?

    init(transferTransaction: RemoteTransactionDTO? = nil) {
        self.transferTransaction = transferTransaction
    }

    var body: some View {
        RemoteMovementEditorSurface(kind: .transfer(transferTransaction), initialAccountID: nil)
    }
}

@available(iOS 26.0, *)
private struct RemoteMovementEditorSurface: View {
    enum Kind {
        case transaction(RemoteTransactionDTO?)
        case transfer(RemoteTransactionDTO? = nil)
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
    @State private var showingCategoryPicker = false
    @State private var isSaving = false
    @State private var mutationError: AppError?
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
        case let .transfer(value): transaction = value; subscription = nil
        case let .subscription(value): transaction = nil; subscription = value
        }
        _mode = State(initialValue: subscription != nil ? .subscription : (transaction?.kind == .income ? .income : .expense))
        _accountID = State(initialValue: (transaction != nil || subscription != nil) ? (subscription?.accountID ?? transaction?.accountID) : nil)
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
        switch kind {
        case let .transaction(value): return value
        case let .transfer(value): return value
        case .subscription: return nil
        }
    }

    private var subscription: RemoteSubscriptionDTO? {
        if case let .subscription(value) = kind { return value }
        return nil
    }

    private var isTransfer: Bool {
        switch kind {
        case .transfer: return true
        case let .transaction(tx): return tx?.kind == .transfer
        case .subscription: return false
        }
    }

    private var isSubscription: Bool {
        if case .subscription = kind { return true }
        return false
    }

    private var isEditing: Bool { transaction != nil || subscription != nil }
    private var isEditingTransaction: Bool { transaction != nil && !isTransfer && !isSubscription }

    var body: some View {
        NavigationStack { editorContent }
            .dynamicTypeSize(...DynamicTypeSize.accessibility5)
            .modifier(RemoteEditorSheetPresentation(compact: isTransfer, isEditingTransaction: isEditingTransaction))
            .onAppear {
                normalizeSelections()
                syncRecurrenceSelection()
            }
            .onChange(of: store.activeAccounts.count) { _ in normalizeSelections() }
            .onChange(of: sourceID) { _ in normalizeSelections() }
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

                if let mutationError {
                    InlineMutationErrorView(error: mutationError) {
                        self.mutationError = nil
                    }
                }
            }
            .padding(.horizontal, 17)
            .padding(.top, 12)
            .padding(.bottom, isTransfer ? 26 : 12)
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
                        Sa7totLoader(size: .compact)
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
        .sheet(isPresented: $showingCategoryPicker) {
            RemoteMovementCategoryPickerView(
                selectedCategoryID: $categoryID,
                income: mode == .income
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
            if !isTransfer { accountCarousel }
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
                Button { showingCategoryPicker = true } label: {
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
                                            descriptor: CategoryIconPresentation.descriptor(for: category),
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

                            Button { showingCategoryPicker = true } label: {
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

    private var accountCarousel: some View {
        RemoteHorizontalAccountPicker(
            title: AppLocalization.string("common.account"),
            accounts: store.activeAccounts,
            selection: $accountID
        )
    }

    private var subscriptionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                }
            }

            accountCarousel
            compactNoteRow
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: isTransfer ? 8 : 14) {
            if isTransfer {
                transferAccountSelectionSection
            }

            compactNoteRow
        }
    }

    private var transferAccountSelectionSection: some View {
        VStack(spacing: 4) {
            RemoteHorizontalAccountPicker(
                title: AppLocalization.string("transfer.from"),
                accounts: store.activeAccounts,
                selection: $sourceID,
                disabledID: destinationID,
                compact: true
            )

            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.Outline.opacity(0.35))
                    .frame(height: 1)

                Button {
                    swapTransferAccounts()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.AppSecondarySurface)
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(Color.Outline.opacity(0.4), lineWidth: 0.8))
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.PrimaryText)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.string("action.swap"))

                Rectangle()
                    .fill(Color.Outline.opacity(0.35))
                    .frame(height: 1)
            }
            .padding(.vertical, 2)

            RemoteHorizontalAccountPicker(
                title: AppLocalization.string("transfer.to"),
                accounts: store.activeAccounts,
                selection: $destinationID,
                disabledID: sourceID,
                compact: true
            )
        }
    }

    private func swapTransferAccounts() {
        guard let currentSource = sourceID, let currentDest = destinationID else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
            sourceID = currentDest
            destinationID = currentSource
        }
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

    private var compactNoteRow: some View {
        HStack(spacing: 10) {
            Label(AppLocalization.string("common.note"), systemImage: "note.text")
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note)
                    .font(.subheadline)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .background(Color.AppSecondarySurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        } else if isEditing {
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
        mutationError = nil
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
                mutationError = AppError.from(error)
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
                        occurredAt: isEditing ? occurredAt : Date.now,
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
                mutationError = AppError.from(error)
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
            guard let anchorDate = Self.remoteDateOnly(from: isEditing ? occurredAt : Date.now) else { return }
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
                mutationError = AppError.from(error)
            }
            isSaving = false
        }
    }
}

@available(iOS 26.0, *)
private struct RemoteEditorSheetPresentation: ViewModifier {
    let compact: Bool
    let isEditingTransaction: Bool

    func body(content: Content) -> some View {
        if compact {
            content
                .presentationDetents([.fraction(0.60), .large])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(AnyShapeStyle(Color.AppPageBackground.opacity(0.14)))
        } else if isEditingTransaction {
            content
                .presentationDetents([.height(448), .large])
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
private struct RemoteHorizontalAccountPicker: View {
    let title: String
    let accounts: [RemoteAccountDTO]
    @Binding var selection: UUID?
    var disabledID: UUID? = nil
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            Text(title)
                .font(.system(compact ? .footnote : .subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Color.SubtitleText)
                .padding(.horizontal, 2)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: compact ? 7 : 10) {
                        ForEach(accounts) { account in
                            let isSelected = account.id == selection
                            let isDisabled = account.id == disabledID

                            Button {
                                selection = account.id
                            } label: {
                                HStack(spacing: compact ? 4 : 6) {
                                    Text(account.name)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)

                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: compact ? 10 : 11, weight: .bold))
                                    }
                                }
                                .font(.system(compact ? .subheadline : .body, design: .rounded).weight(isSelected ? .semibold : .regular))
                                .frame(minHeight: compact ? 36 : 44)
                                .padding(.horizontal, compact ? 10 : 13)
                                .background(Color.AppSecondarySurface, in: Capsule())
                                .opacity(isDisabled ? 0.38 : 1.0)
                            }
                            .buttonStyle(.plain)
                            .disabled(isDisabled)
                            .accessibilityLabel(account.name)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                            .id(account.id)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                }
                .frame(minHeight: compact ? 40 : 52)
                .onAppear {
                    if let selection {
                        proxy.scrollTo(selection, anchor: .center)
                    }
                }
                .onChange(of: selection) { value in
                    guard let value else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(value, anchor: .center) }
                }
            }
        }
    }
}

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
                    Text(account.name)
                }
            }
        } label: {
            HStack(spacing: 8) {
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
private struct AccountManagementCard: View {
    let account: RemoteAccountDTO
    let snapshot: RemoteAccountSnapshotDTO?

    private var liveBalanceMinor: Int64 {
        snapshot?.balanceMinor ?? account.openingBalanceMinor
    }

    private var liveCurrencyCode: String {
        snapshot?.currencyCode ?? account.currencyCode
    }

    private var liveExponent: Int {
        snapshot?.currencyExponent ?? account.currencyExponent
    }

    private var typeTag: String {
        if account.isArchived {
            return AppLocalization.string("account.archived").uppercased()
        }
        return localizedAccountType(account.type).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Image("Sa7totCardIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                Spacer()

                Text("SA7TOT")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(Color.white.opacity(0.6))
            }

            Spacer(minLength: 8)

            Text(account.name)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            HStack(alignment: .lastTextBaseline) {
                Text(remoteAmount(liveBalanceMinor, currencyCode: liveCurrencyCode, exponent: liveExponent))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 12)

                Text(typeTag)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(height: 116)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AccountCardGradientPreset.gradient(forPrimaryHex: account.color))
        }
        .opacity(account.isArchived ? 0.6 : 1.0)
    }
}

@available(iOS 26.0, *)
struct RemoteAccountListView: View {
    @EnvironmentObject private var store: FinancialRemoteStore
    @EnvironmentObject private var appToastCoordinator: AppToastCoordinator
    @State private var showingNewAccount = false
    @State private var editingAccount: RemoteAccountDTO?

    var body: some View {
        List {
            if store.accounts.isEmpty {
                ContentUnavailableView(AppLocalization.key("account.empty"), systemImage: "building.columns", description: Text(AppLocalization.key("account.emptyDescription")))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(store.accounts) { account in
                    Button {
                        editingAccount = account
                    } label: {
                        AccountManagementCard(
                            account: account,
                            snapshot: store.cachedSnapshot(for: account.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !account.isArchived {
                            Button {
                                Task {
                                    do { try await store.archiveAccount(account.id) }
                                    catch { appToastCoordinator.showError(titleKey: "error.mutation.archive.title", error: AppError.from(error)) }
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(AppLocalization.key("account.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewAccount = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(AppLocalization.key("account.new"))
            }
        }
        .sheet(isPresented: $showingNewAccount) {
            RemoteAccountEditorView(
                account: nil,
                defaultCurrencyCode: "EUR"
            )
            .environmentObject(store)
            .environmentObject(appToastCoordinator)
        }
        .sheet(item: $editingAccount) { account in
            RemoteAccountEditorView(account: account)
                .environmentObject(store)
                .environmentObject(appToastCoordinator)
        }
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
private struct AccountCardPreviewView: View {
    let name: String
    let type: String
    let currencyCode: String
    let balanceMinor: Int64?
    let iconName: String
    let colorHex: String
    var currencyExponent: Int = 2
    var incomeMinor: Int64? = nil
    var expensesMinor: Int64? = nil
    var hideBalances: Bool = false
    var showCents: Bool = true
    var handoff: CGFloat = 0.0
    var compact: Bool = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayName: String {
        trimmedName.isEmpty ? AppLocalization.string("account.new") : trimmedName
    }

    private var typeTitle: String {
        if let option = RemoteAccountTypeOption.allCases.first(where: { $0.rawValue == type }) {
            return AppLocalization.string(option.titleKey)
        }
        return localizedAccountType(type)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Row: Fixed Sa7tot App Icon + Subtle SA7TOT Wordmark
            HStack(alignment: .center) {
                Image("Sa7totCardIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 34 : 40, height: compact ? 34 : 40)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 7.5 : 9, style: .continuous))
                    .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1.5)

                Spacer()

                Text("SA7TOT")
                    .font(.system(size: compact ? 9 : 10, weight: .bold, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: compact ? 8 : 12)

            // Account Name
            Text(displayName)
                .font(.system(size: compact ? 16 : 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: compact ? 4 : 8)

            // Balance
            Text(remoteAmount(balanceMinor ?? 0, currencyCode: currencyCode, exponent: currencyExponent, showCents: showCents))
                .font(.system(size: compact ? 24 : 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .blur(radius: hideBalances ? remotePrivacyBlurRadius : 0)
                .opacity(hideBalances ? 0.72 : 1)
                .animation(remotePrivacyTransition, value: hideBalances)

            Spacer(minLength: compact ? 4 : 8)

            // Sub-Bottom Row: Income / Expense summary (if provided) + Account Type Tag
            HStack(alignment: .center, spacing: 10) {
                if let incomeMinor, let expensesMinor {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.IncomeGreen)
                        Text(remoteAmount(abs(incomeMinor), currencyCode: currencyCode, exponent: currencyExponent, showCents: showCents))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .monospacedDigit()
                    }

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.AlertRed)
                        Text(remoteAmount(-abs(expensesMinor), currencyCode: currencyCode, exponent: currencyExponent, showCents: showCents))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .monospacedDigit()
                    }
                    .opacity(1 - handoff)
                }

                Spacer(minLength: 0)

                Text(typeTitle.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(compact ? 16 : 20)
        .aspectRatio(1.6, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                AccountCardGradientPreset.gradient(forPrimaryHex: colorHex)

                if compact {
                    Color.white.opacity(0.08)

                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.05), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(
                        colors: [.white.opacity(0.12), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: compact ? [.white.opacity(0.35), .white.opacity(0.10)] : [.white.opacity(0.22), .white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        }
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocalization.key("account.preview"))
    }
}

@available(iOS 26.0, *)
private struct AccountCardGradientPickerView: View {
    @Binding var selectedColorHex: String

    private var matchedPreset: AccountCardGradientPreset? {
        AccountCardGradientPreset.match(hex: selectedColorHex)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(AccountCardGradientPreset.all) { preset in
                    let isSelected = matchedPreset?.id == preset.id

                    Button {
                        selectedColorHex = preset.primaryHex
                    } label: {
                        ZStack {
                            Circle()
                                .fill(preset.gradient)
                                .frame(width: 38, height: 38)
                                .shadow(color: preset.primaryColor.opacity(0.3), radius: 3, x: 0, y: 1.5)

                            if isSelected {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2.5)
                                    .frame(width: 44, height: 44)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.displayName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
    }
}

@available(iOS 26.0, *)
struct RemoteAccountEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinancialRemoteStore
    @EnvironmentObject private var appToastCoordinator: AppToastCoordinator
    let account: RemoteAccountDTO?
    let defaultCurrencyCode: String

    @State private var name: String
    @State private var type: String
    @State private var currencyCode: String
    @State private var openingBalance: String
    @State private var iconName: String
    @State private var color: String
    @State private var mutationError: AppError?
    @State private var isSaving = false
    @State private var isArmedForReplacement = false
    @FocusState private var isBalanceFocused: Bool

    init(account: RemoteAccountDTO?, defaultCurrencyCode: String = "EUR") {
        self.account = account
        self.defaultCurrencyCode = defaultCurrencyCode
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? "other")
        _currencyCode = State(initialValue: account?.currencyCode ?? defaultCurrencyCode)
        _openingBalance = State(initialValue: account.map { remoteAccountDecimalString($0.openingBalanceMinor, exponent: $0.currencyExponent) } ?? remoteAccountDecimalString(0, exponent: 2))
        _iconName = State(initialValue: account?.iconName ?? "building.columns.fill")
        _color = State(initialValue: account?.color ?? "#5E7CE2")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    AccountCardPreviewView(
                        name: name,
                        type: type,
                        currencyCode: currencyCode,
                        balanceMinor: parsedOpeningBalance ?? 0,
                        iconName: iconName,
                        colorHex: color,
                        compact: true
                    )
                    .frame(maxWidth: 295)
                    .padding(.top, 4)

                    AccountCardGradientPickerView(selectedColorHex: $color)

                    VStack(spacing: 6) {
                        Text(AppLocalization.string("common.name").uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(Color.SubtitleText)

                        VStack(spacing: 6) {
                            TextField(AppLocalization.string("common.name"), text: $name)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()

                            Rectangle()
                                .fill(Color.PrimaryText.opacity(0.18))
                                .frame(height: 1)
                        }
                        .frame(maxWidth: 260)
                    }
                    .padding(.horizontal, 20)

                    VStack(alignment: .center, spacing: 8) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(RemoteAccountTypeOption.allCases) { option in
                                    let isSelected = type == option.rawValue
                                    Button {
                                        type = option.rawValue
                                    } label: {
                                        Text(AppLocalization.key(option.titleKey))
                                            .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                                            .foregroundStyle(isSelected ? Color.black : Color.PrimaryText.opacity(0.8))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(
                                                isSelected ? Color.white : Color.AppSecondarySurface,
                                                in: Capsule()
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    VStack(spacing: 6) {
                        Text(AppLocalization.string("account.initialBalance").uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(Color.SubtitleText)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(remoteCurrencySymbol(for: currencyCode))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.SubtitleText)

                            TextField("0,00", text: $openingBalance)
                                .font(RemoteClashDisplayFont.font(size: 28))
                                .monospacedDigit()
                                .keyboardType(.decimalPad)
                                .fixedSize(horizontal: true, vertical: false)
                                .focused($isBalanceFocused)
                                .onChange(of: isBalanceFocused) { _, isFocused in
                                    if isFocused {
                                        isArmedForReplacement = true
                                    } else {
                                        if openingBalance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            openingBalance = "0,00"
                                        }
                                        isArmedForReplacement = false
                                    }
                                }
                                .onChange(of: openingBalance) { oldValue, newValue in
                                    if isBalanceFocused && isArmedForReplacement && !newValue.isEmpty && newValue != oldValue {
                                        isArmedForReplacement = false
                                        if newValue.count >= oldValue.count {
                                            if let lastChar = newValue.last, (lastChar.isNumber || lastChar == "," || lastChar == ".") {
                                                openingBalance = String(lastChar)
                                            }
                                        }
                                    }
                                }
                                .accessibilityLabel(AppLocalization.key("account.initialBalance"))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                    if let mutationError {
                        InlineMutationErrorView(error: mutationError) {
                            self.mutationError = nil
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
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
                            Sa7totLoader(size: .compact)
                        } else {
                            Text(AppLocalization.key("action.save"))
                        }
                    }
                    .frame(minWidth: 44)
                    .disabled(isSaving || !isValid)
                }
            }
        }
        .presentationDetents([.height(590), .fraction(0.92)])
        .presentationCornerRadius(28)
        .presentationBackground(AnyShapeStyle(Color.AppPageBackground.opacity(0.14)))
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
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

    private func save() {
        guard !isSaving, isValid, let amount = parsedOpeningBalance else { return }
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCurrency.count == 3 else {
            mutationError = .validation(message: AppLocalization.string("account.validationError"))
            return
        }
        mutationError = nil
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
                mutationError = AppError.from(error)
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
    @EnvironmentObject private var appToastCoordinator: AppToastCoordinator
    @State private var selectedFilter: CategoryFilter = .expense
    @State private var showingNewCategory = false
    @State private var editingCategory: RemoteCategoryDTO?
    @State private var activatingPresetKeys: Set<String> = []

    var body: some View {
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
                        categoryRow(category)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Picker(AppLocalization.key("category.filter"), selection: $selectedFilter) {
                        Text(AppLocalization.key("category.expenses")).tag(CategoryFilter.expense)
                        Text(AppLocalization.key("category.incomes")).tag(CategoryFilter.income)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, -16)

                    Text(AppLocalization.key("category.active"))
                }
                .padding(.horizontal, 0)
                .padding(.top, 4)
                .padding(.bottom, 4)
                .textCase(nil)
            }

            if !suggestedPresets.isEmpty {
                Section(header: Text(AppLocalization.key("category.suggested"))) {
                    ForEach(suggestedPresets) { preset in
                        Button { activate(preset) } label: {
                            HStack(spacing: 12) {
                                CategoryIconView(
                                    descriptor: .sfSymbol(preset.symbolName),
                                    role: .category,
                                    tint: Color(hex: preset.defaultColor),
                                    accessibilityLabel: preset.localizedTitle
                                )
                                .frame(width: 44, height: 44)

                                Text(preset.localizedTitle)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer(minLength: 8)
                                if activatingPresetKeys.contains(preset.key) {
                                    Sa7totLoader(size: .compact)
                                } else {
                                    Image(systemName: "plus")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.tint)
                                        .frame(width: 32, height: 32)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .disabled(activatingPresetKeys.contains(preset.key))
                        .accessibilityLabel(AppLocalization.format("category.addSuggested", preset.localizedTitle))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.easeInOut(duration: 0.2), value: store.categories.map(\.id))
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
                .environmentObject(appToastCoordinator)
        }
        .sheet(item: $editingCategory) { category in
            RemoteCategoryEditorView(category: category)
                .environmentObject(store)
                .environmentObject(appToastCoordinator)
        }
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

    private var suggestedPresets: [CategoryPreset] {
        let activePresetKeys = Set(filteredCategories.compactMap(\.presetKey))
        let customNames = Set(
            filteredCategories
                .filter { $0.presetKey == nil }
                .map { normalizedDisplayName($0.name) }
        )

        return CategoryPresetCatalog.presets(income: selectedFilter.isIncome).filter { preset in
            !activePresetKeys.contains(preset.key) && !customNames.contains(normalizedDisplayName(preset.localizedTitle))
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: RemoteCategoryDTO) -> some View {
        Group {
            if category.presetKey == nil {
                Button { editingCategory = category } label: {
                    categoryRowContent(category, showsChevron: true)
                }
            } else {
                categoryRowContent(category, showsChevron: false)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task {
                    do { try await store.deleteCategory(category.id) }
                    catch { appToastCoordinator.showError(titleKey: "error.mutation.delete.title", error: AppError.from(error)) }
                }
            } label: {
                Label(AppLocalization.key("action.delete"), systemImage: "trash")
            }
        }
    }

    private func categoryRowContent(_ category: RemoteCategoryDTO, showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            CategoryIconView(
                descriptor: CategoryIconPresentation.descriptor(for: category),
                role: .category,
                tint: Color(hex: category.color),
                accessibilityLabel: category.name
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.presetKey.flatMap { key in
                    CategoryPresetCatalog.all.first(where: { $0.key == key })?.localizedTitle
                } ?? category.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(AppLocalization.key(category.income ? "category.income" : "category.expense"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }

    private func activate(_ preset: CategoryPreset) {
        guard !activatingPresetKeys.contains(preset.key) else { return }
        activatingPresetKeys.insert(preset.key)
        Task {
            do {
                _ = try await store.activateCategoryPreset(preset)
            } catch {
                appToastCoordinator.showError(titleKey: "error.mutation.save.title", error: AppError.from(error))
            }
            activatingPresetKeys.remove(preset.key)
        }
    }

    private func normalizedDisplayName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
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
    @State private var mutationError: AppError?
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

                    if let mutationError {
                        InlineMutationErrorView(error: mutationError) {
                            self.mutationError = nil
                        }
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
                            Sa7totLoader(size: .compact)
                        } else {
                            Text(AppLocalization.key("action.save"))
                        }
                    }
                    .frame(minWidth: 44)
                    .disabled(isSaving || trimmedName.isEmpty)
                }
            }
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
        mutationError = nil
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
                mutationError = AppError.from(error)
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
    let minY: CGFloat?
    let height: CGFloat
}

private struct RemoteBalanceHeaderMetricsKey: PreferenceKey {
    static var defaultValue = RemoteBalanceHeaderMetrics(minY: nil, height: 175)

    static func reduce(value: inout RemoteBalanceHeaderMetrics, nextValue: () -> RemoteBalanceHeaderMetrics) {
        if let next = nextValue().minY {
            value = RemoteBalanceHeaderMetrics(minY: next, height: nextValue().height)
        } else if value.minY == nil {
            value = nextValue()
        }
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

private struct MovementRecedingScrollEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else if #available(iOS 17.0, *) {
            content.visualEffect { content, geometryProxy in
                let frame = geometryProxy.frame(in: .named("RemoteHomeScroll"))
                let topEdge = frame.minY
                let startThreshold: CGFloat = 118
                let endThreshold: CGFloat = 28

                let rawProgress = topEdge < startThreshold ? min(max((startThreshold - topEdge) / (startThreshold - endThreshold), 0), 1) : 0
                let progress = rawProgress * rawProgress * (3 - (2 * rawProgress))
                let fadeStart: CGFloat = 0.25
                let rawFadeProgress = min(max((rawProgress - fadeStart) / (1 - fadeStart), 0), 1)
                let fadeProgress = rawFadeProgress * rawFadeProgress * (3 - (2 * rawFadeProgress))
                let scale = 1.0 - (0.015 * progress)
                let opacity = 1.0 - (0.50 * fadeProgress)
                let yOffset = 7.0 * progress

                return content
                    .scaleEffect(scale, anchor: .top)
                    .opacity(opacity)
                    .offset(y: yOffset)
            }
        } else {
            content
        }
    }
}
