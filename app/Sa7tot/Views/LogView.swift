//
//  LogView.swift
//  xpenz
//
//  Created by Rafael Soh on 19/5/22.
//

import CloudKitSyncMonitor
import CoreData
import CoreText
import Foundation
import SwiftUIIntrospect
import SwiftUI
import UIKit

private func homeSignedAmountColor(_ value: Double, positive: Color, neutral: Color) -> Color {
    if value < 0 { return Color.AlertRed }
    return value > 0 ? positive : neutral
}

private let privacyBlurRadius: CGFloat = 16
private let privacyTransition = Animation.easeInOut(duration: 0.22)

private enum ClashDisplayFont {
    static let name = "ClashDisplay-Bold"

    private static func register() -> Bool {
        guard let url = Bundle.main.url(forResource: "ClashDisplay-Bold", withExtension: "otf") else {
            assertionFailure("Clash Display Bold font asset is missing from the app bundle")
            return false
        }

        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)

#if DEBUG
        assert(UIFont(name: name, size: 12) != nil, "Clash Display Bold runtime font name could not be resolved")
#endif

        return UIFont(name: name, size: 12) != nil
    }

    static func font(size: CGFloat) -> Font {
        guard register() else { return .system(size: size, weight: .bold) }
        return .custom(name, size: size)
    }

    static func compactFont() -> Font {
        guard register() else { return .system(.title3, design: .rounded).weight(.bold) }
        return .custom(name, size: 20, relativeTo: .title3)
    }
}

// Shared by existing non-navigation buttons; retained when the obsolete
// custom tab-bar file was removed.
struct BouncyButton: ButtonStyle {
    var duration: Double
    var scale: Double

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: duration), value: configuration.isPressed)
    }
}

struct LogView: View {
#if !targetEnvironment(simulator)
    @ObservedObject var syncMonitor = SyncMonitor.shared
#endif

    private var cloudSyncSucceeded: Bool {
#if targetEnvironment(simulator)
        return false
#else
        return syncMonitor.syncStateSummary == .succeeded
#endif
    }

    @State var updatedRecurring = false

    @FetchRequest(sortDescriptors: []) private var transactions: FetchedResults<Transaction>
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "order", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ],
        predicate: AccountQuery.activePredicate
    ) private var activeAccounts: FetchedResults<Account>

    @EnvironmentObject var dataController: DataController
    @Environment(\.managedObjectContext) var moc

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true
    @AppStorage("hideBalances", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) private var hideBalances = false

    var topEdge: CGFloat

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    // top bar
    @State var navBarText = ""

    @State var filter = FilterType.all
    @Binding var selectedAccountID: NSManagedObjectID?

    // filters
    @State var categoryFilter: Category?
    @State var dateFilter = Date.now
    @State var weekFilter = Date.now
    @State var monthFilter = Date.now
    @State var income = false

    var bottomEdge: CGFloat
    var launchAdd: Bool
    var onAdd: (Account?) -> Void
    var usesNativeNavigation = false

    init(
        topEdge: CGFloat,
        bottomEdge: CGFloat,
        launchAdd: Bool,
        selectedAccountID: Binding<NSManagedObjectID?>,
        onAdd: @escaping (Account?) -> Void,
        usesNativeNavigation: Bool = false
    ) {
        self.topEdge = topEdge
        self.bottomEdge = bottomEdge
        self.launchAdd = launchAdd
        self._selectedAccountID = selectedAccountID
        self.onAdd = onAdd
        self.usesNativeNavigation = usesNativeNavigation
    }

    // drag to open
//    enum PullToReach {
//        case none, search, filter
//    }

//    @State var pullStatus: PullToReach = .none
//    @State var released: PullToReach = .none

    @State var progress = 0.0
    @State private var displayedContentIsEmpty = false
    @State private var balanceCollapseProgress: CGFloat = 0
    @State private var expandedBalanceHeaderHeight: CGFloat = 175
    private let compactBalanceHeaderHeight: CGFloat = 54

    private var balanceHandoff: CGFloat {
        min(max((balanceCollapseProgress - 0.50) / 0.28, 0), 1)
    }

    private var selectedAccount: Account? {
        guard let selectedAccountID else { return activeAccounts.first }
        return activeAccounts.first(where: { $0.objectID == selectedAccountID }) ?? activeAccounts.first
    }

    private var activeAccountIDs: [NSManagedObjectID] {
        activeAccounts.map(\.objectID)
    }

    private var selectedAccountCurrentTransactions: [Transaction] {
        guard let selectedAccount else { return [] }
        return transactions.filter {
            $0.wrappedDate <= Date.now && AccountBalanceService.transactionBelongs($0, to: selectedAccount)
        }
    }

    private var selectedAccountBalance: Double {
        guard let selectedAccount else { return 0 }
        return AccountBalanceService.balance(for: selectedAccount, transactions: selectedAccountCurrentTransactions)
    }

    private var selectedAccountCurrency: String {
        selectedAccount?.currencyCode ?? currency
    }

    private var selectedAccountCurrencySymbol: String {
        Locale.current.localizedCurrencySymbol(forCurrencyCode: selectedAccountCurrency) ?? currencySymbol
    }

    private func validateSelectedAccount() {
        if let selectedAccount, selectedAccountID == nil || selectedAccountID != selectedAccount.objectID {
            selectedAccountID = selectedAccount.objectID
        } else if selectedAccount == nil {
            selectedAccountID = nil
        }
    }

    @ViewBuilder
    var body: some View {
        if usesNativeNavigation {
            navigationContent
        } else {
            NavigationView {
                navigationContent
            }
            .navigationViewStyle(.stack)
        }
    }

    private var navigationContent: some View {
            Group {
        if selectedAccount == nil {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 5) {
                Sa7totIcon(systemName: "tray.full.fill", role: .status, tint: .secondary)
                    .font(.system(size: 56, weight: .medium))
                    .frame(width: 75, height: 75)
                    .padding(.bottom, 20)
                    .accessibility(hidden: true)

                Text("Nessun conto")
                    .font(.system(.title2, design: .rounded).weight(.medium))
//                    .font(.system(size: 23.5, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.PrimaryText.opacity(0.8))

                Text("Aggiungi un conto per iniziare")
                    .font(.system(.body, design: .rounded).weight(.medium))
//                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.SubtitleText.opacity(0.7))
            }
            .padding(.horizontal, 30)
            .frame(height: 250, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: 250)
                .sa7totScrollDisabled(transactions.isEmpty)
            .background(Color.AppPageBackground)

        } else {
            VStack(spacing: 0) {
                if filter != .all && filter != .recurring && filter != .upcoming {
                    VStack(spacing: 18) {
                        HStack {
                            Spacer()

                            switch filter {
                            case .category:
                                filterTagView(text: "filter-tag-category")
                            case .day:
                                filterTagView(text: "filter-tag-day")
                            case .week:
                                filterTagView(text: "filter-tag-week")
                            case .month:
                                filterTagView(text: "filter-tag-month")
                            case .type:
                                filterTagView(text: "filter-tag-type")
                            case .all, .recurring, .upcoming:
                                EmptyView()
                            }

                            Spacer()
                        }

                        switch filter {
                        case .category:
                            CategoryStepperView(categoryFilter: $categoryFilter)
                        case .day:
                            DateStepperView(date: $dateFilter)
                        case .week:
                            WeekStepperView(showingDate: $weekFilter)
                        case .month:
                            MonthStepperView(showingDate: $monthFilter)
                        case .type:
                            IncomeFilterToggleView(income: $income)
                        case .all, .recurring, .upcoming:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 25)
                    .frame(height: 110, alignment: .top)
                    .padding(.top, 10)
                }

                ZStack(alignment: .top) {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                Color.clear
                                    .frame(height: 0)
                                    .id("movements-top")
                            if filter == .all, let selectedAccount {
                                AccountInsightsPager(
                                    accounts: Array(activeAccounts),
                                    selectedAccountID: $selectedAccountID,
                                    transactions: Array(transactions),
                                    showCents: showCents,
                                    hideBalances: hideBalances,
                                    collapseProgress: balanceCollapseProgress,
                                    handoff: balanceHandoff
                                )
                                .opacity(1 - balanceHandoff)
                                .overlay(alignment: .top) {
                                    GeometryReader { proxy in
                                        Color.clear
                                            .preference(
                                                key: HomeBalanceHeaderMetricsKey.self,
                                                value: HomeBalanceHeaderMetrics(
                                                    minY: proxy.frame(in: .named("HomeScroll")).minY,
                                                    height: proxy.size.height
                                                )
                                            )
                                    }
                                    .allowsHitTesting(false)
                                }
                            }

                            TransactionsList(
                                filter: filter,
                                account: selectedAccount,
                                currencyCode: selectedAccountCurrency,
                                category: categoryFilter,
                                date: dateFilter,
                                week: weekFilter,
                                month: monthFilter,
                                income: income
                            )
                                .padding(.horizontal, 20)

                            if filter == .all {
                                // Explicit terminal content gives the native scroll view
                                // enough legal travel for the balance header to collapse.
                                // The system bottom safe-area inset remains the only tab-bar inset.
                                Color.clear
                                    .frame(height: 180)
                                    .allowsHitTesting(false)
                            }
                            }
                        }
                        .coordinateSpace(name: "HomeScroll")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .sa7totScrollDisabled(displayedContentIsEmpty)
                        .onPreferenceChange(EmptyStatePreferenceKey.self) { isEmpty in
                            displayedContentIsEmpty = isEmpty
                        }
                        .modifier(HomeScrollProgressModifier { offset in
                            let collapseDistance = max(1, expandedBalanceHeaderHeight - compactBalanceHeaderHeight)
                            let nextProgress = min(max(offset / collapseDistance, 0), 1)
                            guard abs(nextProgress - balanceCollapseProgress) > 0.001 else { return }
                            balanceCollapseProgress = nextProgress
                        })
                        .onChange(of: selectedAccountID) { _ in
                            proxy.scrollTo("movements-top", anchor: .top)
                        }
                    }

                    if #unavailable(iOS 26.0) {
                        LinearGradient(
                            colors: [Color.AppPageBackground.opacity(0.82), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 28)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onPreferenceChange(HomeBalanceHeaderMetricsKey.self) { metrics in
                    expandedBalanceHeaderHeight = metrics.height
                    let collapseDistance = max(1, metrics.height - compactBalanceHeaderHeight)
                    let nextProgress = min(max(-metrics.minY / collapseDistance, 0), 1)
                    guard abs(nextProgress - balanceCollapseProgress) > 0.001 else { return }
                    balanceCollapseProgress = nextProgress
                }

//
//                CustomRefreshView {
//                    VStack {
//
//                    }
//
//                } onRefresh: {
//                    searchMode = true
//                }
//

//                ScrollView(showsIndicators: false) {
//                    if filter == .all {
//                        LogInsightsView(navBarText: $navBarText, showCents: showCents, currencySymbol: currencySymbol)
//
//                    }
//
//
//                    TransactionsList(filter: filter, category: categoryFilter, date: dateFilter, week: weekFilter, month: monthFilter, income: income)
//                        .zIndex(0)
//                        .padding(.horizontal, 20)
//                        .padding(.bottom, 70 + bottomEdge)
                ////                        .offsetExtractor(coordinateSpace: "Scroll") { rect in
                ////                            DispatchQueue.main.async {
                ////                                print(rect.minY)
                ////                                pullStatus = rect.minY > 355 ? (rect.minY > 410 ? .filter : .search) : .none
                ////                            }
                ////                        }
//                }
//                .frame(maxWidth: .infinity, maxHeight: .infinity)
//                .onReceive(scrollDelegate.gestureEnded) { _ in
//                    if pullStatus == .filter {
//                        showFilter = true
//                        released = .filter
//                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
//                    } else if pullStatus == .search {
//                        released = .search
//                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                            searchMode = true
//                        }
//
//                    }
//                }
            }
//            .onAppear(perform: scrollDelegate.addGesture)
//            .onDisappear(perform: scrollDelegate.removeGesture)
            .background(Color.AppPageBackground)
            .onChange(of: cloudSyncSucceeded) { succeeded in
                if succeeded && !updatedRecurring {
                    dataController.updateRecurringTransactions()
                    updatedRecurring = true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                        updatedRecurring = false
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                if cloudSyncSucceeded && !updatedRecurring {
                    dataController.updateRecurringTransactions()
                    updatedRecurring = true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                        updatedRecurring = false
                    }
                } else if !NSUbiquitousKeyValueStore.default.bool(forKey: "icloud_sync") {
                    dataController.updateRecurringTransactions()
                }
            }
            .onAppear {
                if !NSUbiquitousKeyValueStore.default.bool(forKey: "icloud_sync") {
                    dataController.updateRecurringTransactions()
                }
            }
            .onChange(of: filter) { _ in
                balanceCollapseProgress = 0
            }
            .onAppear {
                validateSelectedAccount()
            }
            .onChange(of: activeAccountIDs) { _ in
                validateSelectedAccount()
            }
            .onChange(of: selectedAccountID) { _ in
                balanceCollapseProgress = 0
            }
//            .animation(.spring(duration: 0.5), value: released)
//            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: pullStatus)
//            .onChange(of: pullStatus) { newValue in
//                if newValue != .none && released == .none {
//                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
//                }
//            }
//            .onChange(of: released) { _ in
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                    released = .none
//                }
//            }
        }
            }
            .background {
                NativeFilterMenuBridge(filter: $filter, hideBalances: $hideBalances)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if filter == .all {
                        Group {
                            if let selectedAccount {
                                CompactBalanceToolbarTitle(
                                    accountName: selectedAccount.name ?? "Conto",
                                    showCents: showCents,
                                    currencySymbol: selectedAccountCurrencySymbol,
                                    netTotal: (abs(selectedAccountBalance), selectedAccountBalance >= 0),
                                    hideBalances: hideBalances
                                )
                            }
                        }
                        .opacity(balanceHandoff)
                        .offset(y: 4 * (1 - balanceHandoff))
                        .allowsHitTesting(false)
                        .accessibilityHidden(balanceHandoff < 0.5)
                    }
                }

            }
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: launchAdd) { newValue in
                if newValue {
                    onAdd(selectedAccount)
                }
            }
        }
    @ViewBuilder
    func filterTagView(text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.system(.body, design: .rounded).weight(.medium))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            Button {
                withAnimation(.easeIn(duration: 0.15)) {
                    filter = .all
                }
            } label: {
                Image(systemName: "xmark")
//                    .resizable()
//                    .frame(width: 11, height: 11)
                    .font(.system(.caption, design: .rounded).weight(.regular))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundColor(Color.PrimaryText.opacity(0.7))
            }
                    .accessibilityLabel("rimuovi filtro")
        }
        .padding(4)
        .padding(.horizontal, 6)
        .background(Color.AppSecondarySurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
//        .font(.system(size: 17, weight: .medium, design: .rounded))
        .foregroundColor(Color.PrimaryText)
    }
}

private struct HomeBalanceHeaderMetrics: Equatable {
    let minY: CGFloat
    let height: CGFloat
}

private struct HomeBalanceHeaderMetricsKey: PreferenceKey {
    static var defaultValue = HomeBalanceHeaderMetrics(minY: 0, height: 170)

    static func reduce(value: inout HomeBalanceHeaderMetrics, nextValue: () -> HomeBalanceHeaderMetrics) {
        // The expanded header is a single measurement source.
        value = nextValue()
    }
}

private struct HomeScrollProgressModifier: ViewModifier {
    let onOffsetChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            let trackedContent = content.onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                geometry.contentOffset.y
            }, action: { _, offset in
                onOffsetChange(offset)
            })

            if #available(iOS 26.0, *) {
                trackedContent.scrollEdgeEffectStyle(.soft, for: .top)
            } else {
                trackedContent
            }
        } else {
            content
        }
    }
}

struct CompactBalanceToolbarTitle: View {
    let accountName: String
    let showCents: Bool
    let currencySymbol: String
    let netTotal: (value: Double, positive: Bool)
    let hideBalances: Bool

    var formattedAmount: String {
        String(format: showCents ? "%.2f" : "%.0f", netTotal.value)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(accountName)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundColor(Color.SubtitleText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(netTotal.positive ? currencySymbol : "-\(currencySymbol)")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundColor(Color.SubtitleText)
                    .layoutPriority(1)

                Text(formattedAmount)
                    .font(ClashDisplayFont.compactFont())
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
                    .layoutPriority(0)
                    .blur(radius: hideBalances ? privacyBlurRadius : 0)
                    .opacity(hideBalances ? 0.72 : 1)
                    .animation(privacyTransition, value: hideBalances)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .accessibilityHidden(hideBalances)
            }
        }
        .lineLimit(1)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hideBalances ? "Saldo nascosto" : "\(accountName), saldo \(netTotal.positive ? currencySymbol : "-\(currencySymbol)")\(formattedAmount)")
    }
}

private struct AccountInsightsPager: View {
    let accounts: [Account]
    @Binding var selectedAccountID: NSManagedObjectID?
    let transactions: [Transaction]
    let showCents: Bool
    let hideBalances: Bool
    let collapseProgress: CGFloat
    let handoff: CGFloat
    @AppStorage("logViewLineGraph", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) private var lineGraph = false

    private var pageControlReservedSpace: CGFloat {
        accounts.count > 1 ? 24 : 0
    }

    private var pagerHeight: CGFloat {
        (lineGraph ? 190 : 175) + pageControlReservedSpace
    }

    var body: some View {
        TabView(selection: $selectedAccountID) {
            ForEach(accounts) { account in
                AccountInsightsView(
                    account: account,
                    transactions: transactions,
                    showCents: showCents,
                    hideBalances: hideBalances,
                    collapseProgress: collapseProgress,
                    handoff: handoff
                )
                .padding(.bottom, pageControlReservedSpace)
                .tag(Optional(account.objectID))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: pagerHeight)
    }
}

private struct AccountInsightsView: View {
    @EnvironmentObject var dataController: DataController
    let account: Account
    let transactions: [Transaction]
    let showCents: Bool
    let hideBalances: Bool
    let collapseProgress: CGFloat
    let handoff: CGFloat
    @AppStorage("logViewLineGraph", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) private var lineGraph = false
    @AppStorage("logInsightsTimeFrame", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) private var timeframe = 2

    private var currentTransactions: [Transaction] {
        transactions.filter {
            $0.wrappedDate <= Date.now && AccountBalanceService.transactionBelongs($0, to: account)
        }
    }

    private var balance: Double {
        AccountBalanceService.balance(for: account, transactions: currentTransactions)
    }

    private var income: Double {
        currentTransactions.reduce(0) { total, transaction in
            total + (transaction.wrappedType == .income ? transaction.amount : 0)
        }
    }

    private var expenses: Double {
        currentTransactions.reduce(0) { total, transaction in
            total + (transaction.wrappedType == .expense ? transaction.amount : 0)
        }
    }

    private var currencySymbol: String {
        Locale.current.localizedCurrencySymbol(forCurrencyCode: account.currencyCode ?? "EUR") ?? "€"
    }

    private func amountText(_ amount: Double) -> String {
        String(format: showCents ? "%.2f" : "%.0f", amount)
    }

    private var balanceFont: Font {
        ClashDisplayFont.font(size: 84 - (56 * collapseProgress))
    }

    private var lineGraphData: [LineGraphDataPoint] {
        dataController.getLineGraphDataNet(type: timeframe, account: account)
    }

    private var lineGraphRange: Int {
        let calendar = Calendar.current
        if timeframe == 3 {
            let start = calendar.date(from: calendar.dateComponents([.month, .year], from: Date.now)) ?? Date.now
            return calendar.dateComponents([.day], from: start, to: Date.now).day.map { $0 + 1 } ?? 1
        }
        if timeframe == 4 {
            let start = calendar.date(from: calendar.dateComponents([.year], from: Date.now)) ?? Date.now
            return calendar.dateComponents([.month], from: start, to: Date.now).month.map { $0 + 1 } ?? 1
        }
        return calendar.dateComponents([.day], from: calendar.date(byAdding: .day, value: -7, to: Date.now) ?? Date.now, to: Date.now).day ?? 7
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: max(0, 6 - (4 * collapseProgress))) {
                Text(account.name ?? "Conto")
                    .font(.system(size: 19 - (4 * collapseProgress), design: .rounded).weight(.medium))
                    .foregroundColor(Color.PrimaryText.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(balance >= 0 ? currencySymbol : "-\(currencySymbol)")
                        .font(.system(size: 34 - (8 * collapseProgress), design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                        .layoutPriority(1)

                    Text(amountText(abs(balance)))
                        .font(balanceFont)
                        .foregroundColor(Color.PrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .allowsTightening(true)
                        .layoutPriority(0)
                        .blur(radius: hideBalances ? privacyBlurRadius : 0)
                        .opacity(hideBalances ? 0.72 : 1)
                        .animation(privacyTransition, value: hideBalances)
                }
            }
            .padding(.top, 8 - (4 * collapseProgress))

            if income != 0 || expenses != 0 {
                HStack {
                    Text("+\(amountText(income))")
                        .font(.system(size: 24 - (6 * collapseProgress), design: .rounded).weight(.medium))
                        .minimumScaleFactor(0.5)
                        .monospacedDigit()
                        .foregroundColor(Color.IncomeGreen)
                        .blur(radius: hideBalances ? privacyBlurRadius : 0)
                        .opacity(hideBalances ? 0.72 : 1)
                        .animation(privacyTransition, value: hideBalances)
                        .lineLimit(1)
                        .accessibilityHidden(hideBalances)

                    DottedLine()
                        .stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                        .frame(width: 1.7, height: 15)
                        .foregroundColor(Color.Outline)

                    Text("-\(amountText(expenses))")
                        .font(.system(size: 24 - (6 * collapseProgress), design: .rounded).weight(.medium))
                        .minimumScaleFactor(0.5)
                        .monospacedDigit()
                        .foregroundColor(Color.AlertRed)
                        .blur(radius: hideBalances ? privacyBlurRadius : 0)
                        .opacity(hideBalances ? 0.72 : 1)
                        .animation(privacyTransition, value: hideBalances)
                        .lineLimit(1)
                        .accessibilityHidden(hideBalances)
                }
                .padding(.top, 8)
                .opacity(1 - handoff)
                .frame(height: 31 * (1 - handoff))
                .clipped()
            }

            if lineGraph && lineGraphData.count > 1 {
                LineGraph(
                    data: lineGraphData,
                    green: (lineGraphData.first?.amount ?? 0) <= (lineGraphData.last?.amount ?? 0),
                    type: timeframe,
                    range: lineGraphRange
                )
                .frame(height: 25)
                .padding(.horizontal, 60)
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(minHeight: lineGraph ? 190 : 175)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(hideBalances ? "\(account.name ?? "Conto"), saldo nascosto" : "\(account.name ?? "Conto"), saldo \(balance >= 0 ? currencySymbol : "-\(currencySymbol)")\(amountText(abs(balance)) )")
    }
}

struct NumberView: AnimatableModifier {
    var number: Double
    var dynamicTypeSize: DynamicTypeSize
    let netTotal: Bool
    let positive: Bool
    let hideBalances: Bool
    var collapseProgress: CGFloat = 0

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    var fontSize: CGFloat {
        let baseSize: CGFloat
        switch dynamicTypeSize {
        case .xSmall:
            baseSize = 72
        case .small:
            baseSize = 76
        case .medium:
            baseSize = 80
        case .large:
            baseSize = 84
        case .xLarge:
            baseSize = 88
        case .xxLarge:
            baseSize = 92
        case .xxxLarge:
            baseSize = 96
        default:
            baseSize = 84
        }
        return baseSize - ((baseSize - 28) * collapseProgress)
    }
    var animatableData: Double {
        get { number }
        set { number = newValue }
    }

    func body(content _: Content) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(netTotal ? (positive ? currencySymbol : "-\(currencySymbol)") : currencySymbol)
                .font(.system(size: 34 - (8 * collapseProgress), design: .rounded))
                .foregroundColor(Color.SubtitleText)

            Text("\(number, specifier: showCents  ? "%.2f" : "%.0f")")
                .font(.system(size: fontSize, weight: .regular, design: .rounded))
                .foregroundColor(Color.PrimaryText)
                .monospacedDigit()
                .blur(radius: hideBalances ? privacyBlurRadius : 0)
                .opacity(hideBalances ? 0.72 : 1)
                .animation(privacyTransition, value: hideBalances)
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hideBalances ? "Importo nascosto" : "\(netTotal ? (positive ? currencySymbol : "-\(currencySymbol)") : currencySymbol)\(String(format: showCents ? "%.2f" : "%.0f", number))")

    }
}

struct LogInsightsView: View {
    @EnvironmentObject var dataController: DataController
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    @Binding var navBarText: String

    let showCents: Bool
    let currencySymbol: String
    let netTotal: (value: Double, positive: Bool)
    let hideBalances: Bool
    var collapseProgress: CGFloat = 0
    var handoff: CGFloat = 0

    @AppStorage("logInsightsTimeFrame", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var timeframe = 2
    @AppStorage("logInsightsType", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var insightsType = 1

    @AppStorage("logViewLineGraph", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var lineGraph: Bool = false

    var range: Int {
        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = Sa7totWeekday.storedSelection.rawValue
        calendar.minimumDaysInFirstWeek = 4

        if timeframe == 3 {
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)

            let thisMonth = calendar.date(from: dateComponents) ?? Date.now
            let numberOfDays = calendar.dateComponents([.day], from: thisMonth, to: Date.now)

            return (numberOfDays.day ?? 0) + 1
        } else if timeframe == 4 {
            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            let thisYear = calendar.date(from: dateComponents) ?? Date.now

            let numberOfMonths = calendar.dateComponents([.month], from: thisYear, to: Date.now)

            return (numberOfMonths.month ?? 0) + 1
        } else {
            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)
            let thisWeek = calendar.date(from: dateComponents) ?? Date.now
            let numberOfDays = calendar.dateComponents([.day], from: thisWeek, to: Date.now)

            return (numberOfDays.day ?? 0) + 1
        }
    }

    var totalSpent: Double {
        return dataController.getLogViewTotalSpent(type: 5)
    }

    var totalIncome: Double {
        return dataController.getLogViewTotalIncome(type: 5)
    }

    var lineGraphData: [LineGraphDataPoint] {
        if insightsType == 1 {
            return dataController.getLineGraphDataNet(type: timeframe)
        } else if insightsType == 2 {
            return dataController.getLineGraphData(income: true, type: timeframe)
        } else {
            return dataController.getLineGraphData(income: false, type: timeframe)
        }
    }

    var lineGraphGreen: Bool {
        if insightsType == 1 {
            return (lineGraphData.first?.amount ?? 0.0) < (lineGraphData.last?.amount ?? 0.0)
        } else if insightsType == 2 {
            return true
        } else {
            return false
        }
    }

    var amount: Double {
        if insightsType == 1 {
            return netTotal.value
        } else if insightsType == 2 {
            return totalIncome
        } else {
            return totalSpent
        }
    }

    var headingText: String {
        if insightsType == 1 {
            return "Saldo totale"
        } else if insightsType == 2 {
        return "Entrate"
        } else {
        return "Spese"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: max(0, 6 - (4 * collapseProgress))) {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(headingText))
                        .font(.system(size: 19 - (4 * collapseProgress), design: .rounded).weight(.medium))
                        .foregroundColor(Color.PrimaryText.opacity(0.9))
                }

                EmptyView()
                    .modifier(NumberView(
                        number: amount,
                        dynamicTypeSize: _dynamicTypeSize.wrappedValue,
                        netTotal: insightsType == 1,
                        positive: netTotal.positive,
                        hideBalances: hideBalances,
                        collapseProgress: collapseProgress
                    ))
            }
            .padding(.top, 8 - (4 * collapseProgress))
            .contentShape(Rectangle())
            .contextMenu {
                if insightsType != 3 {
                    Button {
                        insightsType = 3
                    } label: {
                        Label("Spesa totale", systemImage: "minus")
                    }
                }

                if insightsType != 2 {
                    Button {
                        insightsType = 2
                    } label: {
                        Label("Entrate totali", systemImage: "plus")
                    }
                }

                if insightsType != 1 {
                    Button {
                        insightsType = 1
                    } label: {
                        Label("Saldo totale", systemImage: "alternatingcurrent")
                    }
                }
            }

            if totalSpent != 0 && totalIncome != 0 && insightsType == 1 {
                HStack {
//                    if showCents {
//                        Text("+\(totalIncome, specifier: "%.2f")")
//                            .font(.system(size: 18, weight: .medium, design: .rounded))
//                            .foregroundColor(Color.IncomeGreen)
//                            .lineLimit(1)
//                    } else {
//                        Text("+\(Int(floor(totalIncome)))")
//                            .font(.system(size: 18, weight: .medium, design: .rounded))
//                            .foregroundColor(Color.IncomeGreen)
//                            .lineLimit(1)
//                    }

                    Text("+\(formatNumber(showCents: showCents, number: totalIncome))")
                        .font(.system(size: 24 - (6 * collapseProgress), design: .rounded).weight(.medium))
                        .minimumScaleFactor(0.5)
                        .monospacedDigit()
//                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(Color.IncomeGreen)
                        .blur(radius: hideBalances ? privacyBlurRadius : 0)
                        .opacity(hideBalances ? 0.72 : 1)
                        .animation(privacyTransition, value: hideBalances)
                        .lineLimit(1)
                        .accessibilityHidden(hideBalances)

                    DottedLine()
                        .stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                        .frame(width: 1.7, height: 15)
                        .foregroundColor(Color.Outline)

                    Text("-\(formatNumber(showCents: showCents, number: totalSpent))")
                        .font(.system(size: 24 - (6 * collapseProgress), design: .rounded).weight(.medium))
                        .minimumScaleFactor(0.5)
                        .monospacedDigit()
//                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(Color.AlertRed)
                        .blur(radius: hideBalances ? privacyBlurRadius : 0)
                        .opacity(hideBalances ? 0.72 : 1)
                        .animation(privacyTransition, value: hideBalances)
                        .lineLimit(1)
                        .accessibilityHidden(hideBalances)

//                    if showCents {
//                        Text("-\(totalSpent, specifier: "%.2f")")
//                            .font(.system(size: 18, weight: .medium, design: .rounded))
//                            .foregroundColor(Color.AlertRed)
//                            .lineLimit(1)
//                    } else {
//                        Text("-\(Int(floor(totalSpent)))")
//                            .font(.system(size: 18, weight: .medium, design: .rounded))
//                            .foregroundColor(Color.AlertRed)
//                            .lineLimit(1)
//                    }
                }
                .padding(.top, 8)
                .opacity(incomeExpenseOpacity)
                .frame(height: 31 * incomeExpenseOpacity)
                .clipped()
            }

            if lineGraph {
                LineGraph(data: lineGraphData, green: lineGraphGreen, type: timeframe, range: range)
                    .frame(height: 25)
                    .padding(.horizontal, 60)
                    .padding(.top, 16)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(minHeight: lineGraph ? 190 : 175)
        .accessibilityHidden(handoff >= 0.5)
    }

    func formatNumber(showCents: Bool, number: Double) -> String {
        if showCents {
            return String(format: "%.2f", number)
        } else {
            return String(format: "%d", Int(floor(number)))
        }
    }

    private var incomeExpenseOpacity: CGFloat {
        1 - min(max((collapseProgress - 0.30) / 0.25, 0), 1)
    }
}

private func movementSearchPredicate(_ searchQuery: String) -> NSPredicate {
    let beginPredicate = NSPredicate(format: "%K BEGINSWITH[cd] %@", #keyPath(Transaction.note), searchQuery)
    let containPredicate = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(Transaction.note), searchQuery)
    let categoryPredicate = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(Transaction.category.name), searchQuery)
    let sourcePredicate = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(Transaction.account.name), searchQuery)
    let destinationPredicate = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(Transaction.destinationAccount.name), searchQuery)

    var predicates = [beginPredicate, containPredicate, categoryPredicate, sourcePredicate, destinationPredicate]
    if let amount = Double(searchQuery) {
        predicates.append(NSPredicate(format: "amount == %@", NSNumber(value: amount)))
    }
    return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
}

struct SearchView: View {
    @Binding var searchQuery: String

    var body: some View {
        Group {
            if searchQuery.isEmpty {
                Text("Cerca nei movimenti")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    FilteredSearchView(searchQuery: searchQuery)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.AppPageBackground)
    }
}

struct FilteredSearchView: View {
    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>

    var searchQuery: String

    var body: some View {
        VStack {
            if searchQuery != "" && transactions.count == 0 {
                VStack(spacing: 2) {
                    Text("📭️")
                        .font(.system(size: 50))
                        .padding(.bottom, 15)
                    Text("Nessun movimento trovato")
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(Color.PrimaryText)
                    Text("Prova un'altra ricerca")
                        .font(.system(.subheadline, design: .rounded).weight(.regular))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                }
                .frame(alignment: .center)
                .opacity(0.8)
                .padding(.top, 80)
            }

            ListView(transactions: _transactions)
        }
        .frame(maxHeight: .infinity)
    }

    init(searchQuery: String) {
        _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
            SortDescriptor(\.day, order: .reverse),
            SortDescriptor(\.date, order: .reverse)
        ], predicate: movementSearchPredicate(searchQuery))

        self.searchQuery = searchQuery
    }
}

private struct NativeFilterMenuBridge: UIViewControllerRepresentable {
    @Binding var filter: FilterType
    @Binding var hideBalances: Bool

    func makeUIViewController(context: Context) -> FilterMenuViewController {
        FilterMenuViewController(filter: $filter, hideBalances: $hideBalances)
    }

    func updateUIViewController(_ viewController: FilterMenuViewController, context: Context) {
        viewController.filter = $filter
        viewController.hideBalances = $hideBalances
        viewController.installMenuIfNeeded()
    }
}

private final class FilterMenuViewController: UIViewController {
    var filter: Binding<FilterType>
    var hideBalances: Binding<Bool>
    private weak var installedNavigationItem: UINavigationItem?
    private weak var installedBarButtonItem: UIBarButtonItem?
    private weak var installedPrivacyButtonItem: UIBarButtonItem?

    init(filter: Binding<FilterType>, hideBalances: Binding<Bool>) {
        self.filter = filter
        self.hideBalances = hideBalances
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
        DispatchQueue.main.async { [weak self] in
            self?.installMenuIfNeeded()
        }
    }

    func installMenuIfNeeded() {
        guard let navigationItem = navigationController?.topViewController?.navigationItem else { return }

        if installedNavigationItem !== navigationItem || installedBarButtonItem == nil || installedPrivacyButtonItem == nil {
            let barButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "line.3.horizontal.decrease"),
                menu: makeFilterMenu()
            )
            barButtonItem.accessibilityLabel = "Filtra"
            barButtonItem.accessibilityValue = filter.wrappedValue.italianTitle

            let privacyButtonItem = UIBarButtonItem(
                image: UIImage(systemName: hideBalances.wrappedValue ? "eye.slash" : "eye"),
                style: .plain,
                target: self,
                action: #selector(toggleBalanceVisibility)
            )
            privacyButtonItem.accessibilityLabel = hideBalances.wrappedValue ? "Mostra saldo" : "Nascondi saldo"
            privacyButtonItem.accessibilityValue = hideBalances.wrappedValue ? "Saldo nascosto" : "Saldo visibile"

            navigationItem.rightBarButtonItems = [barButtonItem, privacyButtonItem]
            installedNavigationItem = navigationItem
            installedBarButtonItem = barButtonItem
            installedPrivacyButtonItem = privacyButtonItem
        } else {
            installedBarButtonItem?.menu = makeFilterMenu()
            installedBarButtonItem?.accessibilityValue = filter.wrappedValue.italianTitle
            installedPrivacyButtonItem?.image = UIImage(systemName: hideBalances.wrappedValue ? "eye.slash" : "eye")
            installedPrivacyButtonItem?.accessibilityLabel = hideBalances.wrappedValue ? "Mostra saldo" : "Nascondi saldo"
            installedPrivacyButtonItem?.accessibilityValue = hideBalances.wrappedValue ? "Saldo nascosto" : "Saldo visibile"
        }
    }

    @objc private func toggleBalanceVisibility() {
        hideBalances.wrappedValue.toggle()
        installMenuIfNeeded()
    }

    private func makeFilterMenu() -> UIMenu {
        let actions = FilterType.allCases.map { option in
            UIAction(
                title: option.italianTitle,
                state: option == filter.wrappedValue ? .on : .off
            ) { [weak self] _ in
                self?.filter.wrappedValue = option
            }
        }

        return UIMenu(title: "Filtro", options: [.singleSelection], children: actions)
    }
}

struct TransactionsList: View {
    var filter: FilterType
    var account: Account?
    var currencyCode: String
    var category: Category?
    var date: Date
    var week: Date
    var month: Date
    var income: Bool

    @AppStorage("showUpcomingTransactions", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showUpcoming: Bool = true
    @AppStorage("showUpcomingTransactionsWhenUpcoming", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showSoon: Bool = false

    @EnvironmentObject var dataController: DataController

    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>

    init(
        filter: FilterType,
        account: Account?,
        currencyCode: String,
        category: Category?,
        date: Date,
        week: Date,
        month: Date,
        income: Bool
    ) {
        self.filter = filter
        self.account = account
        self.currencyCode = currencyCode
        self.category = category
        self.date = date
        self.week = week
        self.month = month
        self.income = income

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg),
            AccountBalanceService.transactionPredicate(for: account)
        ])

        _transactions = SectionedFetchRequest<Date?, Transaction>(
            sectionIdentifier: \.day,
            sortDescriptors: [
                SortDescriptor(\.day, order: .reverse),
                SortDescriptor(\.date, order: .reverse),
                SortDescriptor(\.note)
            ],
            predicate: predicate
        )
    }

    var body: some View {
        VStack {
            if (filter == .all && showUpcoming) || filter == .upcoming {
                FutureListView(account: account, currencyCode: currencyCode, dataController: dataController, filterMode: filter == .upcoming, limitedMode: showSoon)
                    .padding(.top, 10)
            }

            switch filter {
            case .all:
                if transactions.isEmpty {
                    NoResultsView(fullscreen: true)
                } else {
                    ListView(transactions: _transactions, accountCurrency: currencyCode, selectedAccount: account)
                }
            case .category:
                FilteredCategoryView(category: category, account: account, currencyCode: currencyCode)
            case .day:
                FilteredDateView(date: date, account: account, currencyCode: currencyCode)
            case .week:
                FilteredInsightsView(startDate: week, period: .week, account: account, currencyCode: currencyCode)
            case .month:
                FilteredInsightsView(startDate: month, period: .month, account: account, currencyCode: currencyCode)
            case .recurring:
                FilteredRecurringView(account: account, currencyCode: currencyCode)
            case .type:
                FilteredTypeView(income: income, account: account, currencyCode: currencyCode)
            case .upcoming:
                EmptyView()
            }
        }
    }
}

struct ListView: View {
    @SectionedFetchRequest<Date?, Transaction> var transactions: SectionedFetchResults<Date?, Transaction>
    var accountCurrency: String? = nil
    var selectedAccount: Account? = nil

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    private var displayCurrency: String { accountCurrency ?? currency }
    private var displayCurrencySymbol: String {
        Locale.current.localizedCurrencySymbol(forCurrencyCode: displayCurrency) ?? currencySymbol
    }
    
    @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
    var showExpenseOrIncomeSign: Bool = true

    @AppStorage("swapTimeLabel", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var swapTimeLabel: Bool = false

    @EnvironmentObject var toastPresenter: OverallToastPresenter

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(transactions, id: \.id) { day in
                let filtered = filterOutDupes(day: day)
                let dateText = dateConverter(date: day.id ?? Date.now).uppercased()

                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        HStack {
                            Text(dateText)
                            Spacer()

                            Text(filtered.string)
                                .monospacedDigit()
                                .layoutPriority(1)
                        }
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(homeSignedAmountColor(filtered.total, positive: Color.SubtitleText, neutral: Color.SubtitleText))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(displayCurrencySymbol)\(String(format: "%.2f", filtered.total)) spesi \(dateConverterAccessibilityLabel(date: day.id ?? Date.now))")

                        Line()
                            .stroke(Color.Outline, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                    ForEach(filtered.transactions, id: \.id) { transaction in
                        SingleTransactionView(transaction: transaction, showCents: showCents, currencySymbol: displayCurrencySymbol, currency: displayCurrency, swapTimeLabel: swapTimeLabel, future: false, showExpenseOrIncomeSign: showExpenseOrIncomeSign, selectedAccount: selectedAccount)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .contextMenu {
                    if #available(iOS 16.0, *) {
                        Button {
                            guard let image = ImageRenderer(content: SingleDayPhotoView(amountText: filtered.string, dateText: dateText, transactions: filtered.transactions, showCents: showCents, currencySymbol: displayCurrencySymbol, currency: displayCurrency, swapTimeLabel: swapTimeLabel, future: false)).uiImage else {
                                return
                            }

                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)

                            self.toastPresenter.showToast.toggle()
                        } label: {
                            Label("Salva come foto", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .padding(.bottom, 18)
            }
        }
    }

    func filterOutDupes(day: SectionedFetchResults<Date?, Transaction>.Element) -> (transactions: [Transaction], string: String, total: Double) {
        var seen = [Transaction]()
        let filtered = day.filter { entity -> Bool in
            if seen.contains(where: { $0.id == entity.id }) {
                return false
            } else {
                seen.append(entity)
                return true
            }
        }

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = displayCurrency

        if showCents {
            numberFormatter.maximumFractionDigits = 2
        } else {
            numberFormatter.maximumFractionDigits = 0
        }

        let total = dayTotal(dayTransaction: filtered, selectedAccount: selectedAccount)

        let text: String

        if total >= 0 {
            text = "+" + (numberFormatter.string(from: NSNumber(value: total)) ?? "$0")
        } else {
            text = (numberFormatter.string(from: NSNumber(value: total)) ?? "$0")
        }

        return (filtered, text, total)
    }
}

struct FutureListView: View {
    @EnvironmentObject var dataController: DataController

    @FetchRequest private var fetchedResults: FetchedResults<Transaction>
    let account: Account?
    let currencyCode: String
    var filterMode: Bool
    var limitedMode: Bool

    var transactions: [Transaction] {
        if limitedMode {
            let calendar = Calendar.current

            let startOfToday = calendar.startOfDay(for: Date.now)
            let twoWeeksFromStartOfToday = calendar.date(byAdding: .weekOfYear, value: 2, to: startOfToday)!

            let holding = fetchedResults.filter {
                let date = $0.wrappedDate > Date.now ? $0.wrappedDate : $0.nextTransactionDate

                return date < twoWeeksFromStartOfToday
            }

            return holding.sorted { itemA, itemB in
                let date1 = itemA.wrappedDate > Date.now ? itemA.wrappedDate : itemA.nextTransactionDate
                let date2 = itemB.wrappedDate > Date.now ? itemB.wrappedDate : itemB.nextTransactionDate

                return date1 > date2
            }

        } else {
            return fetchedResults.sorted { itemA, itemB in
                let date1 = itemA.wrappedDate > Date.now ? itemA.wrappedDate : itemA.nextTransactionDate
                let date2 = itemB.wrappedDate > Date.now ? itemB.wrappedDate : itemB.nextTransactionDate

                return date1 > date2
            }
        }
    }

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    private var displayCurrencySymbol: String {
        Locale.current.localizedCurrencySymbol(forCurrencyCode: currencyCode) ?? currencySymbol
    }
    
    @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
    var showExpenseOrIncomeSign: Bool = true

    @AppStorage("swapTimeLabel", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var swapTimeLabel: Bool = false

    var total: Double {
        transactions.reduce(0) { total, transaction in
            guard let account else { return total }
            return total + AccountBalanceService.signedMovementAmount(transaction, for: account)
        }
    }

    var totalString: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = currencyCode

        if showCents {
            numberFormatter.maximumFractionDigits = 2
        } else {
            numberFormatter.maximumFractionDigits = 0
        }

        if total >= 0 {
            return "+" + (numberFormatter.string(from: NSNumber(value: total)) ?? "$0")
        } else {
            return numberFormatter.string(from: NSNumber(value: total)) ?? "$0"
        }
    }

    var body: some View {
        if !transactions.isEmpty {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    HStack {
                        Text("IN ARRIVO")
                        Spacer()

                        Text(totalString)
                            .monospacedDigit()
                    }
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(homeSignedAmountColor(total, positive: Color.SubtitleText, neutral: Color.SubtitleText))
                    .accessibilityElement(children: .ignore)

                    Line()
                        .stroke(Color.Outline, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                }
                .padding(.horizontal, 10)

                ForEach(transactions) { transaction in
                    SingleTransactionView(transaction: transaction, showCents: showCents, currencySymbol: displayCurrencySymbol, currency: currencyCode, swapTimeLabel: swapTimeLabel, future: true, showExpenseOrIncomeSign: showExpenseOrIncomeSign, selectedAccount: account)
                }
            }
            .padding(.bottom, 18)
        } else if transactions.isEmpty && filterMode {
            NoResultsView(fullscreen: true)
        } else {
            EmptyView()
        }
    }

    init(account: Account?, currencyCode: String, dataController _: DataController, filterMode: Bool, limitedMode: Bool) {
        let recurringPredicate = NSPredicate(format: "%K > %i", #keyPath(Transaction.recurringType), 0)
        let futurePredicate = NSPredicate(format: "%K > %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let datePredicate = NSCompoundPredicate(type: .or, subpredicates: [recurringPredicate, futurePredicate])
        let andPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            datePredicate,
            AccountBalanceService.transactionPredicate(for: account)
        ])

        _fetchedResults = FetchRequest<Transaction>(sortDescriptors: [], predicate: andPredicate)

        self.account = account
        self.currencyCode = currencyCode
        self.filterMode = filterMode
        self.limitedMode = limitedMode
    }

    init(dataController: DataController, filterMode: Bool, limitedMode: Bool) {
        self.init(
            account: nil,
            currencyCode: UserDefaults(suiteName: "group.com.saied.sa7tot")?.string(forKey: "currency") ?? Locale.current.currencyCode ?? "EUR",
            dataController: dataController,
            filterMode: filterMode,
            limitedMode: limitedMode
        )
    }
}

struct SingleTransactionView: View {
    let transaction: Transaction
    let showCents: Bool
    let currencySymbol: String
    let currency: String
    let swapTimeLabel: Bool
    let future: Bool
    let showExpenseOrIncomeSign: Bool
    let selectedAccount: Account?

    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var transactionManager: OverallTransactionManager

    var transactionAmountString: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = currency

        if showCents {
            numberFormatter.maximumFractionDigits = 2
        } else {
            numberFormatter.maximumFractionDigits = 0
        }

        return numberFormatter.string(from: NSNumber(value: transaction.amount)) ?? "$0"
    }

    private var signedAmount: Double {
        guard let selectedAccount else {
            return transaction.income ? transaction.amount : -transaction.amount
        }
        return AccountBalanceService.signedMovementAmount(transaction, for: selectedAccount)
    }

    private var accessibilityAmount: String {
        let prefix: String
        if transaction.isTransfer, selectedAccount != nil {
            prefix = signedAmount >= 0 ? "+" : "-"
        } else if transaction.income {
            prefix = showExpenseOrIncomeSign ? "+" : ""
        } else {
            prefix = showExpenseOrIncomeSign ? "-" : ""
        }
        return "\(prefix)\(currencySymbol)\(String(format: "%.2f", transaction.wrappedAmount))"
    }

    private var stableTransactionIdentifier: String {
        transaction.objectID.uriRepresentation().absoluteString
    }

    private var canDelete: Bool {
        !(future && transaction.wrappedDate < Date.now && transaction.recurringType > 0)
    }

    var body: some View {
        NativeTransactionContextMenuRow(
            identifier: stableTransactionIdentifier,
            canDelete: canDelete,
            content: transactionRowContent,
            onEdit: {
                transactionManager.toEdit = transaction
            },
            onDelete: {
                transactionManager.toDelete = transaction
                transactionManager.future = future
                transactionManager.showPopup = true
            }
        )
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            transactionManager.detailSelectedAccount = selectedAccount
            transactionManager.toDetail = transaction
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(transaction.wrappedNote), \(accessibilityAmount), Categoria del movimento: \(transaction.category?.wrappedName ?? "Sconosciuta"), Movimento registrato: \(timeConverterAccessibilityLabel(date: transaction.wrappedDate))")
    }

    private var transactionRowContent: some View {
            HStack(spacing: 12) {
                if transaction.isTransfer {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.PrimaryText)
                        .frame(width: 34, height: 34)
                        .background(Color.AppSecondarySurface, in: Circle())
                } else {
                    CategoryLogIconView(iconIdentifier: transaction.category?.iconIdentifier ?? "sf:tag.fill",
                                 categoryName: transaction.category?.wrappedName,
                                 colour: (transaction.category?.wrappedColour ?? "#FFFFFF"), future: future)
                        .fixedSize(horizontal: true, vertical: true)
                        .overlay(alignment: .bottomTrailing) {
                        if transaction.recurringType > 0 {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.DarkIcon)
                                .padding(3)
                                .background(Color.AppSecondarySurface, in: RoundedRectangle(cornerRadius: 6))
                                .offset(x: 5, y: 5)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.isTransfer ? "Trasferimento" : transaction.wrappedNote)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(future ? Color.SubtitleText : Color.PrimaryText)
                        .lineLimit(1)

                    Text(getSubtitle())
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .foregroundColor(future ? Color.EvenLighterText : Color.SubtitleText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if transaction.isTransfer {
                    Text(selectedAccount == nil ? transactionAmountString : "\(signedAmount >= 0 ? "+" : "-")\(transactionAmountString)")
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .monospacedDigit()
                        .foregroundColor(homeSignedAmountColor(signedAmount, positive: future ? Color.SubtitleText : Color.IncomeGreen, neutral: future ? Color.SubtitleText : Color.IncomeGreen))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .layoutPriority(1)
                } else if transaction.income {
                    Text(showExpenseOrIncomeSign ? "+\(transactionAmountString)" : transactionAmountString)
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .monospacedDigit()
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(homeSignedAmountColor(transaction.amount, positive: future ? Color.SubtitleText : Color.IncomeGreen, neutral: future ? Color.SubtitleText : Color.IncomeGreen))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .layoutPriority(1)

                } else {
                    Text(showExpenseOrIncomeSign ? "-\(transactionAmountString)" : transactionAmountString)
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .monospacedDigit()
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(homeSignedAmountColor(-abs(transaction.amount), positive: Color.AlertRed, neutral: Color.AlertRed))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
    }

    func getSubtitle() -> String {
        if transaction.isTransfer {
            return "\(transaction.account?.name ?? "Conto") → \(transaction.destinationAccount?.name ?? "Conto")"
        }
        if future {
            if transaction.wrappedDate > Date.now {
                return dateFormatter(date: transaction.wrappedDate)
            } else {
                return dateFormatter(date: transaction.nextTransactionDate)
            }
        } else {
            if swapTimeLabel {
                return transaction.wrappedCategoryName
            } else {
                return transaction.wrappedDate.sa7totTimeString
            }
        }
    }
}

struct TransactionDetailView: View {
    let transaction: Transaction
    let selectedAccount: Account?

    @Environment(\.dismiss) private var dismiss
    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) private var showCents = true

    private var currencyCode: String {
        selectedAccount?.currencyCode
            ?? transaction.account?.currencyCode
            ?? Locale.current.currencyCode
            ?? "EUR"
    }

    private var currencySymbol: String {
        Locale.current.localizedCurrencySymbol(forCurrencyCode: currencyCode) ?? currencyCode
    }

    private var amountDigits: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = showCents ? 2 : 0
        formatter.maximumFractionDigits = showCents ? 2 : 0
        return formatter.string(from: NSNumber(value: abs(transaction.amount))) ?? "0"
    }

    private var amountPrefix: String {
        if transaction.isTransfer {
            guard let selectedAccount else { return "" }
            return AccountBalanceService.signedMovementAmount(transaction, for: selectedAccount) >= 0 ? "+" : "-"
        }
        return transaction.income ? "+" : "-"
    }

    private var amountAccessibilityValue: String {
        "\(amountPrefix)\(currencySymbol)\(amountDigits)"
    }

    private var amountColor: Color {
        let signedValue: Double
        if transaction.isTransfer {
            guard let selectedAccount else { return Color.SubtitleText }
            signedValue = AccountBalanceService.signedMovementAmount(transaction, for: selectedAccount)
        } else {
            signedValue = transaction.income ? transaction.amount : -transaction.amount
        }
        return homeSignedAmountColor(signedValue, positive: Color.IncomeGreen, neutral: Color.IncomeGreen)
    }

    private var dateValue: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: transaction.wrappedDate)
    }

    private var timeValue: String {
        transaction.wrappedDate.sa7totTimeString
    }

    private var heroTitle: String {
        if transaction.isTransfer {
            return "Trasferimento"
        }
        let categoryName = transaction.category?.wrappedName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return categoryName.isEmpty ? "Movimento" : categoryName
    }

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
                        Text(heroTitle)
                            .font(.system(.title2, design: .rounded).weight(.medium))
                            .foregroundColor(Color.PrimaryText)

                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text("\(amountPrefix)\(currencySymbol)")
                                .font(.system(.headline, design: .rounded).weight(.medium))
                                .foregroundColor(Color.SubtitleText)

                            Text(amountDigits)
                                .font(ClashDisplayFont.font(size: 34))
                                .foregroundColor(amountColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                                .allowsTightening(true)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Importo, \(amountAccessibilityValue)")
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)

                    VStack(spacing: 0) {
                        if !transaction.isTransfer, let categoryName = transaction.category?.wrappedName, !categoryName.isEmpty {
                            detailRow(label: "Categoria", value: categoryName)
                        }
                        if !transaction.isTransfer, let accountName = transaction.account?.name, !accountName.isEmpty {
                            detailRow(label: "Conto", value: accountName)
                        }
                        if transaction.isTransfer {
                            detailRow(label: "Da", value: transaction.account?.name ?? "Conto")
                            detailRow(label: "A", value: transaction.destinationAccount?.name ?? "Conto")
                        }
                        detailRow(label: "Data", value: dateValue)
                        detailRow(label: "Ora", value: timeValue)
                    }

                    if !transaction.wrappedNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nota")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundColor(Color.SubtitleText)

                            Text(transaction.wrappedNote)
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(Color.PrimaryText)
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

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundColor(Color.SubtitleText)

            Spacer(minLength: 12)

            Text(value)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
    }
}

func dateFormatter(date: Date) -> String {
    let dateFormatter = DateFormatter()

    dateFormatter.dateFormat = "d MMM"
    return dateFormatter.string(from: date).uppercased()
}

struct CategoryLogIconView: View {
    let iconIdentifier: String
    let categoryName: String?
    let colour: String
    let future: Bool
    let huge: Bool

    var body: some View {
        CategoryIconView(descriptor: CategoryIconPresentation.descriptor(for: iconIdentifier), role: huge ? .category : .listRow, accessibilityLabel: categoryName ?? "Altro")
            .opacity(future ? 0.6 : 1)
    }

    init(iconIdentifier: String, categoryName: String? = nil, colour: String, future: Bool, huge: Bool = false) {
        self.iconIdentifier = iconIdentifier
        self.categoryName = categoryName
        self.colour = colour
        self.future = future
        self.huge = huge
    }
}

struct BackgroundBlurView: UIViewRepresentable {
    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }

    func updateUIView(_: UIView, context _: Context) {}
}

struct FilteredRecurringView: View {
    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>
    let account: Account?
    let currencyCode: String

    var body: some View {
        VStack(spacing: 30) {
            if transactions.count == 0 {
                NoResultsView(fullscreen: true)
            }

            ListView(transactions: _transactions, accountCurrency: currencyCode, selectedAccount: account)
        }
        .frame(maxHeight: .infinity)
    }

    init(account: Account?, currencyCode: String) {
        let recurringPredicate = NSPredicate(format: "%K = %d", #keyPath(Transaction.onceRecurring), true)
        let datePredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let andPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            recurringPredicate,
            datePredicate,
            AccountBalanceService.transactionPredicate(for: account)
        ])

        _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
            SortDescriptor(\.day, order: .reverse),
            SortDescriptor(\.date, order: .reverse),
            SortDescriptor(\.note, order: .reverse)
        ], predicate: andPredicate)
        self.account = account
        self.currencyCode = currencyCode
    }
}

struct FilteredTypeView: View {
    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>

    var income: Bool
    let account: Account?
    let currencyCode: String

    var body: some View {
        VStack(spacing: 30) {
            if transactions.count == 0 {
                NoResultsView(fullscreen: true)
            }

            ListView(transactions: _transactions, accountCurrency: currencyCode, selectedAccount: account)
        }
        .frame(maxHeight: .infinity)
    }

    init(income: Bool, account: Account?, currencyCode: String) {
        let incomePredicate = NSPredicate(format: "income = %d", income)
        let datePredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let andPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            incomePredicate,
            datePredicate,
            AccountBalanceService.transactionPredicate(for: account)
        ])

        _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
            SortDescriptor(\.day, order: .reverse),
            SortDescriptor(\.date, order: .reverse)
        ], predicate: andPredicate)

        self.income = income
        self.account = account
        self.currencyCode = currencyCode
    }
}

struct FilteredCategoryView: View {
    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>

    var category: Category?
    let account: Account?
    let currencyCode: String

    var body: some View {
        VStack(spacing: 30) {
            if transactions.count == 0 || category == nil {
                NoResultsView(fullscreen: true)
            } else {
                ListView(transactions: _transactions, accountCurrency: currencyCode, selectedAccount: account)
            }
        }
        .frame(maxHeight: .infinity)
    }

    init(category: Category?, account: Account?, currencyCode: String) {
        if let unwrappedCategory = category {
            let categoryPredicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.category), unwrappedCategory)
            let datePredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                categoryPredicate,
                datePredicate,
                AccountBalanceService.transactionPredicate(for: account)
            ])

            _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
                SortDescriptor(\.day, order: .reverse),
                SortDescriptor(\.date, order: .reverse)
            ], predicate: andPredicate)
        } else {
            _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
                SortDescriptor(\.day, order: .reverse),
                SortDescriptor(\.date, order: .reverse)
            ])
        }

        self.category = category
        self.account = account
        self.currencyCode = currencyCode
    }
}

struct FilteredDateView: View {
    @FetchRequest private var transactions: FetchedResults<Transaction>

    var date: Date
    let account: Account?
    let currencyCode: String

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    @AppStorage("swapTimeLabel", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var swapTimeLabel: Bool = false

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true
    
    @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
    var showExpenseOrIncomeSign: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if transactions.count == 0 {
                NoResultsView(fullscreen: true)
            }
            ForEach(transactions) { transaction in
                SingleTransactionView(transaction: transaction, showCents: showCents, currencySymbol: displayCurrencySymbol, currency: currencyCode, swapTimeLabel: swapTimeLabel, future: false, showExpenseOrIncomeSign: showExpenseOrIncomeSign, selectedAccount: account)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var displayCurrencySymbol: String {
        Locale.current.localizedCurrencySymbol(forCurrencyCode: currencyCode) ?? currencySymbol
    }

    init(date: Date, account: Account?, currencyCode: String) {
        let datePredicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.day), date as CVarArg)
        let futurePredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let andPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            futurePredicate,
            datePredicate,
            AccountBalanceService.transactionPredicate(for: account)
        ])

        _transactions = FetchRequest<Transaction>(sortDescriptors: [
            SortDescriptor(\.date, order: .reverse)
        ], predicate: andPredicate)

        self.date = date
        self.account = account
        self.currencyCode = currencyCode
    }
}

struct NoResultsView: View {
    let fullscreen: Bool

    var body: some View {
        Group {
            if fullscreen {
                VStack(spacing: 12) {
                Spacer()

                Image(systemName: "tray.full.fill")
                    .font(.system(.largeTitle, design: .rounded))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                    .font(.system(size: 38, weight: .regular, design: .rounded))
                    .foregroundColor(Color.SubtitleText)

                Text("Nessun movimento trovato.")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundColor(Color.SubtitleText)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: UIScreen.main.bounds.height * 0.7)
                .opacity(0.7)
            } else {
                VStack(spacing: 12) {
                Spacer()

                //            Text("📭️")
                //                .font(.system(size: 45))
                //                .padding(.bottom, 9)
                //                .accessibility(hidden: true)

                Image(systemName: "tray.full.fill")
                    .font(.system(size: 38, weight: .regular, design: .rounded))
                    .foregroundColor(Color.SubtitleText)

                Text("Nessun movimento trovato.")
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundColor(Color.SubtitleText)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .opacity(0.7)
                .padding(.top, 50)
            }
        }
        .preference(key: EmptyStatePreferenceKey.self, value: true)
    }
}

struct EmptyStatePreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    @ViewBuilder
    func sa7totScrollDisabled(_ disabled: Bool) -> some View {
        if #available(iOS 16.0, *) {
            scrollDisabled(disabled)
        } else {
            self
        }
    }
}

struct CategoryStepperView: View {
    @Binding var categoryFilter: Category?
    @EnvironmentObject var dataController: DataController
    @State var income = false
    @State var categories = [Category]()

    var body: some View {
        HStack(spacing: 8) {
            if income {
                Image(systemName: "plus")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.IncomeGreen)
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .aspectRatio(1.0, contentMode: .fit)
//                    .frame(width: 36, height: 36)
                    .background(Color.IncomeGreen.opacity(0.23), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let fetchRequest = dataController.fetchRequestForCategories(income: false)
                        let holding = dataController.results(for: fetchRequest)

                        if holding.isEmpty {
                            return
                        } else {
                            income = false
                            categories = holding
                            categoryFilter = categories[0]
                        }
                    }
            } else {
                Image(systemName: "minus")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.AlertRed)
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .aspectRatio(1.0, contentMode: .fit)
//                    .frame(width: 36, height: 36)
                    .background(Color.AlertRed.opacity(0.23), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let fetchRequest = dataController.fetchRequestForCategories(income: true)
                        let holding = dataController.results(for: fetchRequest)

                        if holding.isEmpty {
                            return
                        } else {
                            income = true
                            categories = holding
                            categoryFilter = categories[0]
                        }
                    }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                ScrollViewReader { value in
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { item in
                            HStack(spacing: 5) {
                                CategoryIconView(descriptor: item.iconDescriptor, role: .inline, accessibilityLabel: item.wrappedName)
                                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                    .font(.system(size: 13))
                                Text(item.wrappedName)
//                                    .font(.system(size: 17.5, weight: .medium, design: .rounded))
                                    .font(.system(.body, design: .rounded).weight(.medium))
                                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            }
                            .id(item.id)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .fixedSize(horizontal: false, vertical: true)
//                            .frame(height: 36)
                            .foregroundColor(Color.PrimaryText)
                            .background(getBackground(category: item), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                if categoryFilter != item {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.Outline,
                                                      style: StrokeStyle(lineWidth: 1.5))
                                }
                            }
                            .onTapGesture {
                                categoryFilter = item
                                withAnimation {
                                    value.scrollTo(item.id, anchor: .leading)
                                }
                            }
//                            .accessibilityElement(children: .ignore)
//                            .accessibilityLabel("filter \(item.wrappedName) transactions button")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .onAppear {
            let fetchRequest = dataController.fetchRequestForCategories(income: income)
            categories = dataController.results(for: fetchRequest)

            if categories.isEmpty {
                categoryFilter = nil
            } else {
                categoryFilter = categories[0]
            }
        }
        .onChange(of: income) { _ in
            if categories.isEmpty {
                categoryFilter = nil
            } else {
                categoryFilter = categories[0]
            }
        }
    }

    func getBackground(category: Category) -> Color {
        if category == categoryFilter {
            return Color.AppSecondarySurface
        } else {
            return Color.AppPageBackground
        }
    }

    init(categoryFilter: Binding<Category?>?) {
        _categoryFilter = categoryFilter ?? Binding.constant(nil)
    }
}

struct IncomeFilterToggleView: View {
    @Binding var income: Bool

    @Namespace var animation

    var body: some View {
        HStack(spacing: 0) {
            Text("Spesa")
//                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(income == false ? Color.PrimaryText : Color.SubtitleText)
                .padding(5.5)
                .padding(.horizontal, 8)
                .background {
                    if income == false {
                        Capsule()
                            .fill(Color.AppSecondarySurface)
                            .matchedGeometryEffect(id: "TAB1", in: animation)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    DispatchQueue.main.async {
                        withAnimation(.easeIn(duration: 0.15)) {
                            income = false
                        }
                    }
                }

            Text("filter-picker-income")
//                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(income == true ? Color.PrimaryText : Color.SubtitleText)
                .padding(5.5)
                .padding(.horizontal, 8)
                .background {
                    if income == true {
                        Capsule()
                            .fill(Color.AppSecondarySurface)
                            .matchedGeometryEffect(id: "TAB1", in: animation)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    DispatchQueue.main.async {
                        withAnimation(.easeIn(duration: 0.15)) {
                            income = true
                        }
                    }
                }
        }
        .padding(3)
        .overlay(Capsule().stroke(Color.Outline.opacity(0.4), lineWidth: 1.3))
    }
}

struct DateStepperView: View {
    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.day)
    ]) private var transactions: FetchedResults<Transaction>

    @Binding var date: Date
    var endDate: Date {
        if transactions.isEmpty {
            return Date.now
        } else {
            return transactions[0].day ?? Date.now
        }
    }

    let currentDate = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: Date.now) ?? Date.now

    var dateString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "d MMM yyyy"

        return dateFormatter.string(from: date)
    }

    var body: some View {
        HStack {
            StepperButtonView(left: true, disabled: date <= endDate) {
                if date > endDate {
                    date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? Date.now
                }
            }
                .accessibilityLabel("giorno precedente")

            Spacer()

            Text(dateString)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                .font(.system(size: 20, weight: .bold, design: .rounded))
                .accessibilityLabel("movimenti del \(dateString)")

            Spacer()

            StepperButtonView(left: false, disabled: date >= currentDate) {
                if date < currentDate {
                    date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? Date.now
                }
            }
                .accessibilityLabel("giorno successivo")
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            date = currentDate
        }
    }
}

struct WeekStepperView: View {
    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.day)
    ]) private var transactions: FetchedResults<Transaction>

    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.day, order: .reverse)
    ], predicate: NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)) private var transactionsReversed: FetchedResults<Transaction>

    @Binding var showingDate: Date
    var endDate: Date {
        if transactions.isEmpty {
            return Date.now
        } else {
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = Sa7totWeekday.storedSelection.rawValue
            calendar.minimumDaysInFirstWeek = 4

            let date = transactions[0].day ?? Date.now

            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)

            return calendar.date(from: dateComponents) ?? Date.now
        }
    }

    @State var startDate = Date.now

    var dateString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "d MMM"

        let endComponents = DateComponents(day: 7, second: -1)
        let endWeekDate = Calendar.current.date(byAdding: endComponents, to: showingDate) ?? Date.now

        return dateFormatter.string(from: showingDate) + " - " + dateFormatter.string(from: endWeekDate)
    }

    var accessibilityDateString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "d MMM"

        let endComponents = DateComponents(day: 7, second: -1)
        let endWeekDate = Calendar.current.date(byAdding: endComponents, to: showingDate) ?? Date.now

        return "showing transactions from " + dateFormatter.string(from: showingDate) + " to " + dateFormatter.string(from: endWeekDate)
    }

    var body: some View {
        HStack {
            StepperButtonView(left: true, disabled: showingDate == endDate) {
                if showingDate > endDate {
                    showingDate = Calendar.current.date(byAdding: .day, value: -7, to: showingDate) ?? Date.now
                }
            }
                .accessibilityLabel("settimana precedente")

            Spacer()

            Text(dateString)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .accessibilityLabel(accessibilityDateString)

            Spacer()

            StepperButtonView(left: false, disabled: showingDate == startDate) {
                if showingDate < startDate {
                    showingDate = Calendar.current.date(byAdding: .day, value: 7, to: showingDate) ?? Date.now
                }
            }
                .accessibilityLabel("settimana successiva")
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            var calendar = Calendar(identifier: .gregorian)

            calendar.firstWeekday = Sa7totWeekday.storedSelection.rawValue
            calendar.minimumDaysInFirstWeek = 4

            let date = transactionsReversed[0].day ?? Date.now

            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)

            startDate = calendar.date(from: dateComponents) ?? Date.now

            showingDate = startDate
        }
    }
}

struct MonthStepperView: View {
    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.day)
    ]) private var transactions: FetchedResults<Transaction>

    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.day, order: .reverse)
    ], predicate: NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)) private var transactionsReversed: FetchedResults<Transaction>

    @Binding var showingDate: Date
    var endDate: Date {
        if transactions.isEmpty {
            return Date.now
        } else {
            let calendar = Calendar(identifier: .gregorian)

            let date = transactions[0].day ?? Date.now

            let dateComponents = calendar.dateComponents([.month, .year], from: date)

            return calendar.date(from: dateComponents) ?? Date.now
        }
    }

    @State var startDate = Date.now

    var dateString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "MMM yyyy"

        return dateFormatter.string(from: showingDate)
    }

    var body: some View {
        HStack {
            StepperButtonView(left: true, disabled: showingDate == endDate) {
                if showingDate > endDate {
                    showingDate = Calendar.current.date(byAdding: .month, value: -1, to: showingDate) ?? Date.now
                }
            }
                .accessibilityLabel("mese precedente")

            Spacer()

            Text(dateString)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .accessibilityLabel("movimenti di \(dateString)")

            Spacer()

            StepperButtonView(left: false, disabled: showingDate == startDate) {
                if showingDate < startDate {
                    showingDate = Calendar.current.date(byAdding: .month, value: 1, to: showingDate) ?? Date.now
                }
            }
                .accessibilityLabel("mese successivo")
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            let calendar = Calendar(identifier: .gregorian)

            let date = transactionsReversed[0].day ?? Date.now

            let dateComponents = calendar.dateComponents([.month, .year], from: date)

            startDate = calendar.date(from: dateComponents) ?? Date.now

            showingDate = startDate
        }
    }
}

struct FilteredInsightsView: View {
    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>
    let account: Account?
    let currencyCode: String

    var body: some View {
        VStack(spacing: 30) {
            if transactions.count == 0 {
                NoResultsView(fullscreen: false)
            }

            ListView(transactions: _transactions, accountCurrency: currencyCode, selectedAccount: account)
        }
        .frame(maxHeight: .infinity)
    }

    init(startDate: Date, income: Bool? = nil, period: InsightsPeriod, account: Account?, currencyCode: String) {
        let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), startDate as CVarArg)

        let endPredicate: NSPredicate

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = Sa7totWeekday.storedSelection.rawValue
        calendar.minimumDaysInFirstWeek = 4

        if period == .week {
            if calendar.isDate(startDate, equalTo: Date.now, toGranularity: .weekOfYear) {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                let next = calendar.date(byAdding: .day, value: 7, to: startDate) ?? Date.now
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        } else if period == .month {
            if calendar.isDate(startDate, equalTo: Date.now, toGranularity: .month) {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                let next = calendar.date(byAdding: .month, value: 1, to: startDate) ?? Date.now
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        } else {
            if calendar.isDate(startDate, equalTo: Date.now, toGranularity: .year) {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                let next = calendar.date(byAdding: .year, value: 1, to: startDate) ?? Date.now
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        }

        let andPredicate: NSCompoundPredicate

        if let unwrappedIncome = income {
            let incomePredicate = NSPredicate(format: "income = %d", unwrappedIncome)
            andPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                startPredicate,
                endPredicate,
                incomePredicate,
                StatisticsTransactionFilter.excludingTransfersPredicate(),
                AccountBalanceService.transactionPredicate(for: account)
            ])
        } else {
            andPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                startPredicate,
                endPredicate,
                StatisticsTransactionFilter.excludingTransfersPredicate(),
                AccountBalanceService.transactionPredicate(for: account)
            ])
        }

        _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
            SortDescriptor(\.day, order: .reverse),
            SortDescriptor(\.date, order: .reverse)
        ], predicate: andPredicate)
        self.account = account
        self.currencyCode = currencyCode
    }
}

func dateConverter(date: Date) -> String {
    let calendar = Calendar.current

    let dateComponents = calendar.dateComponents([.year], from: Date.now)

    let startOfCurrentYear = calendar.date(from: dateComponents) ?? Date.now

    if calendar.isDateInToday(date) {
        return String(localized: "today")
    } else if calendar.isDateInYesterday(date) {
        return String(localized: "yesterday")
    } else if startOfCurrentYear > date {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "EEE, d MMM yy"

        var string = dateFormatter.string(from: date)
        string.insert("'", at: string.index(string.endIndex, offsetBy: -2))

        return string
    } else {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "EEE, d MMM"

        return dateFormatter.string(from: date)
    }
}

func dateConverterAccessibilityLabel(date: Date) -> String {
    let calendar = Calendar.current

    if calendar.isDateInToday(date) {
        return "oggi"
    } else if calendar.isDateInYesterday(date) {
        return "ieri"
    } else {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "EEE, d MMM yyyy"

        return "il " + dateFormatter.string(from: date)
    }
}

func timeConverterAccessibilityLabel(date: Date) -> String {
    date.sa7totTimeString
}

func dayTotal(dayTransaction: [Transaction], selectedAccount: Account? = nil) -> Double {
    var total = 0.0

    dayTransaction.forEach { transaction in
        if let selectedAccount {
            total += AccountBalanceService.signedMovementAmount(transaction, for: selectedAccount)
        } else if transaction.wrappedType == .income {
            total += transaction.amount
        } else if transaction.wrappedType == .expense {
            total -= transaction.amount
        }
    }

    return total
}
