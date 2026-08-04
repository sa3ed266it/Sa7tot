//
//  LogView.swift
//  xpenz
//
//  Created by Rafael Soh on 19/5/22.
//

import CloudKitSyncMonitor
import CoreData
import Foundation
import SwiftUIIntrospect
import SwiftUI

private func homeSignedAmountColor(_ value: Double, positive: Color, neutral: Color) -> Color {
    if value < 0 { return Color.AlertRed }
    return value > 0 ? positive : neutral
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

    @EnvironmentObject var dataController: DataController
    @Environment(\.managedObjectContext) var moc

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true

    var topEdge: CGFloat

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    // top bar
    @State var navBarText = ""

    @State var filter = FilterType.all

    // filters
    @State var categoryFilter: Category?
    @State var dateFilter = Date.now
    @State var weekFilter = Date.now
    @State var monthFilter = Date.now
    @State var income = false

    var bottomEdge: CGFloat
    var launchAdd: Bool
    var onAdd: () -> Void

    // drag to open
//    enum PullToReach {
//        case none, search, filter
//    }

//    @State var pullStatus: PullToReach = .none
//    @State var released: PullToReach = .none

    @State var progress = 0.0
    @State private var balanceCollapseProgress: CGFloat = 0
    @State private var expandedBalanceHeaderHeight: CGFloat = 175
    private let compactBalanceHeaderHeight: CGFloat = 54

    private var balanceHandoff: CGFloat {
        min(max((balanceCollapseProgress - 0.50) / 0.28, 0), 1)
    }

    var body: some View {
        NavigationView {
            Group {
        if transactions.isEmpty {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 5) {
                Sa7totIcon(systemName: "tray.full.fill", role: .status, tint: .secondary)
                    .font(.system(size: 56, weight: .medium))
                    .frame(width: 75, height: 75)
                    .padding(.bottom, 20)
                    .accessibility(hidden: true)

                Text("Your Log is Empty")
                    .font(.system(.title2, design: .rounded).weight(.medium))
//                    .font(.system(size: 23.5, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.PrimaryText.opacity(0.8))

                Text("Press the plus button\nto add your first entry")
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
            .background(Color.PrimaryBackground)

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
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            if filter == .all {
                                LogInsightsView(
                                    navBarText: $navBarText,
                                    showCents: showCents,
                                    currencySymbol: currencySymbol,
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

                            TransactionsList(filter: filter, category: categoryFilter, date: dateFilter, week: weekFilter, month: monthFilter, income: income)
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
                    .modifier(HomeScrollProgressModifier { offset in
                        let collapseDistance = max(1, expandedBalanceHeaderHeight - compactBalanceHeaderHeight)
                        let nextProgress = min(max(offset / collapseDistance, 0), 1)
                        guard abs(nextProgress - balanceCollapseProgress) > 0.001 else { return }
                        balanceCollapseProgress = nextProgress
                    })

                    if #unavailable(iOS 26.0) {
                        LinearGradient(
                            colors: [Color.PrimaryBackground.opacity(0.82), .clear],
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
            .background(Color.PrimaryBackground)
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Aggiungi movimento")
                }

                ToolbarItem(placement: .principal) {
                    if filter == .all {
                        CompactBalanceToolbarTitle(
                            showCents: showCents,
                            currencySymbol: currencySymbol
                        )
                        .opacity(balanceHandoff)
                        .offset(y: 4 * (1 - balanceHandoff))
                        .allowsHitTesting(false)
                        .accessibilityHidden(balanceHandoff < 0.5)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Filtro", selection: $filter) {
                            ForEach(FilterType.allCases, id: \.self) { option in
                                Text(option.italianTitle).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .frame(width: 44, height: 44)
                    }
                    .labelStyle(.iconOnly)
                    .sa7totFilterButtonBorderShape()
                    .sa7totFilterButtonStyle()
                    .accessibilityLabel("Filtra")
                    .accessibilityValue(filter.italianTitle)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: launchAdd) { newValue in
                if newValue {
                    onAdd()
                }
            }
        }
        .navigationViewStyle(.stack)
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
        .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
    @EnvironmentObject var dataController: DataController

    let showCents: Bool
    let currencySymbol: String

    var netTotal: (value: Double, positive: Bool) {
        dataController.getLogViewTotalNet(type: 5)
    }

    var formattedAmount: String {
        String(format: showCents ? "%.2f" : "%.0f", netTotal.value)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("Saldo totale")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundColor(Color.SubtitleText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(netTotal.positive ? currencySymbol : "-\(currencySymbol)")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundColor(Color.SubtitleText)

                Text(formattedAmount)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
        }
        .lineLimit(1)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Saldo totale, \(netTotal.positive ? currencySymbol : "-\(currencySymbol)")\(formattedAmount)")
    }
}

struct NumberView: AnimatableModifier {
    var number: Double
    var dynamicTypeSize: DynamicTypeSize
    let netTotal: Bool
    let positive: Bool
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
            Group {
                Text(netTotal ? (positive ? currencySymbol : "-\(currencySymbol)") : currencySymbol)
                    .font(.system(size: 34 - (8 * collapseProgress), design: .rounded))
                    .foregroundColor(Color.SubtitleText) +

                Text("\(number, specifier: showCents  ? "%.2f" : "%.0f")")
                    .font(.system(size: fontSize, weight: .regular, design: .rounded))
                    .foregroundColor(Color.PrimaryText)
            }
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)

    }
}

struct LogInsightsView: View {
    @EnvironmentObject var dataController: DataController
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    @Binding var navBarText: String

    let showCents: Bool
    let currencySymbol: String
    var collapseProgress: CGFloat = 0
    var handoff: CGFloat = 0

    @AppStorage("logInsightsTimeFrame", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var timeframe = 2
    @AppStorage("logInsightsType", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var insightsType = 1

    @AppStorage("logViewLineGraph", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var lineGraph: Bool = false

    var netTotal: (value: Double, positive: Bool) {
        dataController.getLogViewTotalNet(type: 5)
    }

    var range: Int {
        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = UserDefaults(suiteName: "group.com.saied.sa7tot")?.integer(forKey: "firstWeekday") ?? 0
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
            return "Earned"
        } else {
            return "Spent"
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
                        Label("Total Spent", systemImage: "minus")
                    }
                }

                if insightsType != 2 {
                    Button {
                        insightsType = 2
                    } label: {
                        Label("Total Income", systemImage: "plus")
                    }
                }

                if insightsType != 1 {
                    Button {
                        insightsType = 1
                    } label: {
                        Label("Net Total", systemImage: "alternatingcurrent")
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
//                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(Color.IncomeGreen)
                        .lineLimit(1)

                    DottedLine()
                        .stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                        .frame(width: 1.7, height: 15)
                        .foregroundColor(Color.Outline)

                    Text("-\(formatNumber(showCents: showCents, number: totalSpent))")
                        .font(.system(size: 24 - (6 * collapseProgress), design: .rounded).weight(.medium))
                        .minimumScaleFactor(0.5)
//                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(Color.AlertRed)
                        .lineLimit(1)

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
        .background(Color.PrimaryBackground)
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
        let beginPredicate = NSPredicate(format: "%K BEGINSWITH[cd] %@", #keyPath(Transaction.note), searchQuery)
        let containPredicate = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(Transaction.note), searchQuery)
        let containPredicate1 = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(Transaction.category.name), searchQuery)
        let sourcePredicate = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(Transaction.account.name), searchQuery)
        let destinationPredicate = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(Transaction.destinationAccount.name), searchQuery)

        let compound: NSCompoundPredicate

        // allow searching by amount too
        if let amount = Double(searchQuery) {
            let amountPredicate = NSPredicate(format: "amount == %@", NSNumber(value: amount))
            compound = NSCompoundPredicate(orPredicateWithSubpredicates: [beginPredicate, containPredicate, containPredicate1, sourcePredicate, destinationPredicate, amountPredicate])
        } else {
            compound = NSCompoundPredicate(orPredicateWithSubpredicates: [beginPredicate, containPredicate, containPredicate1, sourcePredicate, destinationPredicate])
        }

        _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
            SortDescriptor(\.day, order: .reverse),
            SortDescriptor(\.date, order: .reverse)
        ], predicate: compound)

        self.searchQuery = searchQuery
    }
}

private extension View {
    @ViewBuilder
    func sa7totFilterButtonBorderShape() -> some View {
        if #available(iOS 17.0, *) {
            buttonBorderShape(.circle)
        } else {
            buttonBorderShape(.roundedRectangle)
        }
    }

    @ViewBuilder
    func sa7totFilterButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            self
        }
    }
}

struct TransactionsList: View {
    var filter: FilterType
    var category: Category?
    var date: Date
    var week: Date
    var month: Date
    var income: Bool

    @AppStorage("showUpcomingTransactions", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showUpcoming: Bool = true
    @AppStorage("showUpcomingTransactionsWhenUpcoming", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showSoon: Bool = false

    @EnvironmentObject var dataController: DataController

    @SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
        SortDescriptor(\.day, order: .reverse),
        SortDescriptor(\.date, order: .reverse),
        SortDescriptor(\.note)
    ], predicate: NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)) private var transactions: SectionedFetchResults<Date?, Transaction>

    var body: some View {
        VStack {
            if (filter == .all && showUpcoming) || filter == .upcoming {
                FutureListView(dataController: dataController, filterMode: filter == .upcoming, limitedMode: showSoon)
                    .padding(.top, 10)
            }

            switch filter {
            case .all:
                ListView(transactions: _transactions)
            case .category:
                FilteredCategoryView(category: category)
            case .day:
                FilteredDateView(date: date)
            case .week:
                FilteredInsightsView(startDate: week, type: 1)
            case .month:
                FilteredInsightsView(startDate: month, type: 2)
            case .recurring:
                FilteredRecurringView()
            case .type:
                FilteredTypeView(income: income)
            case .upcoming:
                EmptyView()
            }
        }
    }
}

struct ListView: View {
    @SectionedFetchRequest<Date?, Transaction> var transactions: SectionedFetchResults<Date?, Transaction>

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }
    
    @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
    var showExpenseOrIncomeSign: Bool = true

    @AppStorage("swapTimeLabel", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var swapTimeLabel: Bool = false

    @EnvironmentObject var toastPresenter: OverallToastPresenter

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(transactions) { day in
                let filtered = filterOutDupes(day: day)
                let dateText = dateConverter(date: day.id ?? Date.now).uppercased()

                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        HStack {
                            Text(dateText)
                            Spacer()

                            Text(filtered.string)
                                .layoutPriority(1)
                        }
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(homeSignedAmountColor(filtered.total, positive: Color.SubtitleText, neutral: Color.SubtitleText))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(currencySymbol)\(String(format: "%.2f", filtered.string)) was spent \(dateConverterAccessibilityLabel(date: day.id ?? Date.now))")

                        Line()
                            .stroke(Color.Outline, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                    ForEach(filtered.transactions, id: \.id) { transaction in
                        SingleTransactionView(transaction: transaction, showCents: showCents, currencySymbol: currencySymbol, currency: currency, swapTimeLabel: swapTimeLabel, future: false, showExpenseOrIncomeSign: showExpenseOrIncomeSign)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .contextMenu {
                    if #available(iOS 16.0, *) {
                        Button {
                            guard let image = ImageRenderer(content: SingleDayPhotoView(amountText: filtered.string, dateText: dateText, transactions: filtered.transactions, showCents: showCents, currencySymbol: currencySymbol, currency: currency, swapTimeLabel: swapTimeLabel, future: false)).uiImage else {
                                return
                            }

                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)

                            self.toastPresenter.showToast.toggle()
                        } label: {
                            Label("Save as Photo", systemImage: "square.and.arrow.up")
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
        numberFormatter.currencyCode = currency

        if showCents {
            numberFormatter.maximumFractionDigits = 2
        } else {
            numberFormatter.maximumFractionDigits = 0
        }

        let total = dayTotal(dayTransaction: filtered)

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
    
    @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
    var showExpenseOrIncomeSign: Bool = true

    @AppStorage("swapTimeLabel", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var swapTimeLabel: Bool = false

    var total: Double {
        transactions.reduce(0) { total, transaction in
            if transaction.wrappedType == .income {
                return total + transaction.amount
            } else if transaction.wrappedType == .expense {
                return total - transaction.amount
            } else {
                return total
            }
        }
    }

    var totalString: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = currency

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
                        Text("UPCOMING")
                        Spacer()

                        Text(totalString)
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
                    SingleTransactionView(transaction: transaction, showCents: showCents, currencySymbol: currencySymbol, currency: currency, swapTimeLabel: swapTimeLabel, future: true, showExpenseOrIncomeSign: showExpenseOrIncomeSign)
                }
            }
            .padding(.bottom, 18)
        } else if transactions.isEmpty && filterMode {
            NoResultsView(fullscreen: true)
        } else {
            EmptyView()
        }
    }

    init(dataController _: DataController, filterMode: Bool, limitedMode: Bool) {
        let recurringPredicate = NSPredicate(format: "%K > %i", #keyPath(Transaction.recurringType), 0)
        let futurePredicate = NSPredicate(format: "%K > %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let andPredicate = NSCompoundPredicate(type: .or, subpredicates: [recurringPredicate, futurePredicate])

        _fetchedResults = FetchRequest<Transaction>(sortDescriptors: [], predicate: andPredicate)

        self.filterMode = filterMode
        self.limitedMode = limitedMode
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
            transactionManager.toEdit = transaction
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(transaction.wrappedNote), \(currencySymbol)\(String(format: "%.2f", transaction.wrappedAmount)), Categoria del movimento: \(transaction.category?.wrappedName ?? "Sconosciuta"), Movimento registrato: \(timeConverterAccessibilityLabel(date: transaction.wrappedDate))")
    }

    private var transactionRowContent: some View {
            HStack(spacing: 12) {
                if transaction.isTransfer {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.PrimaryText)
                        .frame(width: 34, height: 34)
                        .background(Color.SecondaryBackground, in: Circle())
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
                                .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 6))
                                .offset(x: 5, y: 5)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.wrappedNote)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(future ? Color.SubtitleText : Color.PrimaryText)
                        .lineLimit(1)

                    Text(getSubtitle())
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .foregroundColor(future ? Color.EvenLighterText : Color.SubtitleText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if transaction.isTransfer {
                    Text(transactionAmountString)
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .foregroundColor(homeSignedAmountColor(transaction.amount, positive: future ? Color.SubtitleText : Color.PrimaryText, neutral: future ? Color.SubtitleText : Color.PrimaryText))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .layoutPriority(1)
                } else if transaction.income {
                    Text(showExpenseOrIncomeSign ? "+\(transactionAmountString)" : transactionAmountString)
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(homeSignedAmountColor(transaction.amount, positive: future ? Color.SubtitleText : Color.IncomeGreen, neutral: future ? Color.SubtitleText : Color.IncomeGreen))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .layoutPriority(1)

                } else {
                    Text(showExpenseOrIncomeSign ? "-\(transactionAmountString)" : transactionAmountString)
                        .font(.system(.title3, design: .rounded).weight(.medium))
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
            return "Trasferimento: \(transaction.account?.name ?? "Conto") → \(transaction.destinationAccount?.name ?? "Conto")"
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
                let formatter = DateFormatter()
                formatter.dateFormat = "h:mm a"

                return formatter.string(from: transaction.wrappedDate)
            }
        }
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

    var body: some View {
        VStack(spacing: 30) {
            if transactions.count == 0 {
                NoResultsView(fullscreen: true)
            }

            ListView(transactions: _transactions)
        }
        .frame(maxHeight: .infinity)
    }

    init() {
        let recurringPredicate = NSPredicate(format: "%K = %d", #keyPath(Transaction.onceRecurring), true)
        let datePredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [recurringPredicate, datePredicate])

        _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
            SortDescriptor(\.day, order: .reverse),
            SortDescriptor(\.date, order: .reverse),
            SortDescriptor(\.note, order: .reverse)
        ], predicate: andPredicate)
    }
}

struct FilteredTypeView: View {
    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>

    var income: Bool

    var body: some View {
        VStack(spacing: 30) {
            if transactions.count == 0 {
                NoResultsView(fullscreen: true)
            }

            ListView(transactions: _transactions)
        }
        .frame(maxHeight: .infinity)
    }

    init(income: Bool) {
        let incomePredicate = NSPredicate(format: "income = %d", income)
        let datePredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [incomePredicate, datePredicate])

        _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
            SortDescriptor(\.day, order: .reverse),
            SortDescriptor(\.date, order: .reverse)
        ], predicate: andPredicate)

        self.income = income
    }
}

struct FilteredCategoryView: View {
    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>

    var category: Category?

    var body: some View {
        VStack(spacing: 30) {
            if transactions.count == 0 || category == nil {
                NoResultsView(fullscreen: true)
            } else {
                ListView(transactions: _transactions)
            }
        }
        .frame(maxHeight: .infinity)
    }

    init(category: Category?) {
        if let unwrappedCategory = category {
            let categoryPredicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.category), unwrappedCategory)
            let datePredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [categoryPredicate, datePredicate])

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
    }
}

struct FilteredDateView: View {
    @FetchRequest private var transactions: FetchedResults<Transaction>

    var date: Date

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
                SingleTransactionView(transaction: transaction, showCents: showCents, currencySymbol: currencySymbol, currency: currency, swapTimeLabel: swapTimeLabel, future: false, showExpenseOrIncomeSign: showExpenseOrIncomeSign)
            }
        }
        .frame(maxHeight: .infinity)
    }

    init(date: Date) {
        let datePredicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.day), date as CVarArg)
        let futurePredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [futurePredicate, datePredicate])

        _transactions = FetchRequest<Transaction>(sortDescriptors: [
            SortDescriptor(\.date, order: .reverse)
        ], predicate: andPredicate)

        self.date = date
    }
}

struct NoResultsView: View {
    let fullscreen: Bool

    var body: some View {
        if fullscreen {
            VStack(spacing: 12) {
                Spacer()

                Image(systemName: "tray.full.fill")
                    .font(.system(.largeTitle, design: .rounded))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                    .font(.system(size: 38, weight: .regular, design: .rounded))
                    .foregroundColor(Color.SubtitleText)

                Text("No entries found.")
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

                Text("No entries found.")
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundColor(Color.SubtitleText)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .opacity(0.7)
            .padding(.top, 50)
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
                            .foregroundColor(categoryFilter == item ? Color(hex: item.wrappedColour) : Color.PrimaryText)
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
            return Color(hex: category.wrappedColour).opacity(0.3)
        } else {
            return Color.PrimaryBackground
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
            Text("Expense")
//                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(income == false ? Color.PrimaryText : Color.SubtitleText)
                .padding(5.5)
                .padding(.horizontal, 8)
                .background {
                    if income == false {
                        Capsule()
                            .fill(Color.SecondaryBackground)
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
                            .fill(Color.SecondaryBackground)
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
            calendar.firstWeekday = UserDefaults(suiteName: "group.com.saied.sa7tot")?.integer(forKey: "firstWeekday") ?? 0
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

            calendar.firstWeekday = UserDefaults(suiteName: "group.com.saied.sa7tot")?.integer(forKey: "firstWeekday") ?? 0
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
        return "today"
    } else if calendar.isDateInYesterday(date) {
        return "yesterday"
    } else {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "EEE, d MMM yyyy"

        return "on " + dateFormatter.string(from: date)
    }
}

func timeConverterAccessibilityLabel(date: Date) -> String {
    let dateFormatter = DateFormatter()

    dateFormatter.dateFormat = "h:mm a"

    return dateFormatter.string(from: date)
}

func dayTotal(dayTransaction: [Transaction]) -> Double {
    var total = 0.0

    dayTransaction.forEach { transaction in
        if transaction.wrappedType == .income {
            total += transaction.amount
        } else if transaction.wrappedType == .expense {
            total -= transaction.amount
        }
    }

    return total
}
