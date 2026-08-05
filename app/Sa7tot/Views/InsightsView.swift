//
//  InsightsView.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import Foundation
import SwiftUIIntrospect
import Popovers
import SwiftUI

private extension View {
    @ViewBuilder
    func statisticsScrollEdgeEffect() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

struct InsightsView: View {
    @FetchRequest(sortDescriptors: []) private var transactions: FetchedResults<Transaction>

    @AppStorage("chartTimeFrame", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var chartType = 1

    private var didSave = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
    @State private var refreshID = UUID()

    var chartTypeString: String {
        if chartType == 1 {
            return "week"
        } else if chartType == 2 {
            return "month"
        } else if chartType == 3 {
            return "year"
        } else {
            return ""
        }
    }

//    @State private var holdingIncome = false
//    @Namespace var animation

    var body: some View {
        if transactions.isEmpty {
            VStack(spacing: 5) {
                Sa7totIcon(systemName: "chart.line.uptrend.xyaxis", role: .status, tint: .secondary)
                    .font(.system(size: 56, weight: .medium))
                    .frame(width: 75, height: 75)
                    .padding(.bottom, 20)

                Text("Analizza le tue spese")
                    .font(.system(.title2, design: .rounded).weight(.medium))
//                    .font(.system(size: 23.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.PrimaryText.opacity(0.8))
                    .multilineTextAlignment(.center)

                Text("Quando inizierai ad aggiungere movimenti")
                    .font(.system(.body, design: .rounded).weight(.medium))
//                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(Color.SubtitleText.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)
            .frame(height: 250, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
            .background(Color.AppPageBackground)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .navigationTitle("Statistiche")
            .navigationBarTitleDisplayMode(.large)

        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Periodo", selection: $chartType) {
                            Text("settimana").tag(1)
                            Text("mese").tag(2)
                            Text("anno").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .controlSize(.small)
                        .tint(.secondary)
                        .accessibilityLabel("Periodo")
                        .accessibilityValue(chartTypeString)
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 4)
                    .padding(.bottom, 14)

                    if chartType == 1 {
                        WeekGraphView()
                            .id(refreshID)
                    } else if chartType == 2 {
                        MonthGraphView()
                            .id(refreshID)
                    } else if chartType == 3 {
                        YearGraphView()
                            .id(refreshID)
                    }
                }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.AppPageBackground)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .onReceive(self.didSave) { _ in
                self.refreshID = UUID()
            }
            .navigationTitle("Statistiche")
            .navigationBarTitleDisplayMode(.large)
            .statisticsScrollEdgeEffect()
        }
    }
}

struct HorizontalPieChartView: View {
    @FetchRequest private var allCategories: FetchedResults<Category>
    @FetchRequest private var transactions: FetchedResults<Transaction>

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true

    var income: Bool
    var date: Date
    var total: Double {
        var holdingTotal = 0.0

        transactions.forEach { transaction in
            holdingTotal += transaction.amount
        }

        return holdingTotal
    }

    @Binding var chosenAmount: Double
    @Binding var chosenName: String

    @Binding var categoryFilterMode: Bool
    @Binding var categoryFilter: Category?
    @Binding var selectedDate: Date?

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var fontSize: CGFloat {
        switch dynamicTypeSize {
        case .xSmall:
            return 12
        case .small:
            return 13
        case .medium:
            return 14
        case .large:
            return 15
        case .xLarge:
            return 17
        case .xxLarge:
            return 19
        case .xxxLarge:
            return 21
        default:
            return 15
        }
    }

    var percentWidth: CGFloat {
        return "100%".widthOfRoundedString(size: fontSize, weight: .medium) + 4
    }

    var categories: [PowerCategory] {
        var holding = [PowerCategory]()

        for category in allCategories {
            var holdingTotal = 0.0

            transactions.forEach { transaction in
                if transaction.category == category {
                    holdingTotal += transaction.wrappedAmount
                }
            }

            if holdingTotal == 0 {
                continue
            }

            let newCategory = PowerCategory(id: category.id ?? UUID(), category: category, percent: holdingTotal / total, amount: holdingTotal)

            holding.append(newCategory)
        }

        holding.sort(by: { lhs, rhs in
            lhs.percent > rhs.percent
        })

        return holding
    }

    var body: some View {
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !categoryFilterMode {
                    Text("Categorie")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.SubtitleText)

                    GeometryReader { proxy in
                        HStack(spacing: proxy.size.width * 0.015) {
                            ForEach(categories) { category in
                                if category.percent < 0.005 {
                                    EmptyView()
                                } else {
                                    AnimatedHorizontalBarGraph(category: category, index: categories.firstIndex(of: category) ?? 0)
                                        .frame(width: (proxy.size.width * (1.0 - (0.015 * Double(categories.count - 1)))) * category.percent)
                                        .onTapGesture {
                                            withAnimation(.easeInOut) {
                                                if categoryFilter == category.category {
                                                    selectedDate = nil
                                                    categoryFilterMode = false
                                                    categoryFilter = nil
                                                } else {
                                                    selectedDate = nil
                                                    categoryFilterMode = true
                                                    categoryFilter = category.category
                                                    chosenAmount = category.percent * total
                                                    chosenName = category.category.wrappedName
                                                }
                                            }
                                        }
                                        .opacity(categoryFilterMode ? (categoryFilter == category.category ? 1 : 0.5) : 1)
                                        .overlay {
                                            if categoryFilterMode && categoryFilter == category.category {
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .stroke(category.category.statisticsColor, lineWidth: 1.5)
                                            }
                                        }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 17)
                    .padding(.bottom, 10)
                }

                VStack {
                    VStack(spacing: 10) {
                        ForEach(categories, id: \.self) { category in
                            if !categoryFilterMode || categoryFilter == category.category {
                                let boxColor = category.category.statisticsColor

                                HStack(spacing: 10) {

                                    HStack(spacing: 10) {
                                        CategoryIconView(descriptor: category.category.iconDescriptor, role: .category, tint: boxColor, accessibilityLabel: category.category.wrappedName)

                                        Text(category.category.wrappedName)
                                            .font(.system(.title3, design: .rounded).weight(.semibold))
                                            .foregroundColor(Color.PrimaryText)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Text("\(currencySymbol)\(category.amount, specifier: (showCents && category.amount < 100) ? "%.2f" : "%.0f")")
                                        .font(.system(categoryFilterMode && categoryFilter == category.category ? .title3 : .body, design: .rounded).weight(.medium))
                                        .foregroundColor(Color.SubtitleText)
                                        .lineLimit(1)
                                        .layoutPriority(1)

                                    if categoryFilterMode && categoryFilter == category.category {
                                        Button {
                                            withAnimation(.easeInOut) {
                                                selectedDate = nil
                                                categoryFilterMode = false
                                                categoryFilter = nil
                                            }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(.footnote, design: .rounded).weight(.bold))
                                                .foregroundColor(boxColor)
                                                .padding(5)
                                                .background(boxColor.opacity(0.23), in: Circle())
                                        }
                                        .accessibilityLabel("Cancella selezione categoria")

                                    } else {

                                        Text("\(category.percent * 100, specifier: "%.0f")%")
                                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                            .foregroundColor(boxColor)
                                            .padding(.vertical, 3)
                                            .frame(width: percentWidth)
                                            .background(boxColor.opacity(0.23), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                                .padding(.vertical, categoryFilterMode && categoryFilter == category.category ? 10 : 5)
                                .padding(.horizontal, categoryFilterMode && categoryFilter == category.category ? 10 : 0)
                                .background(RoundedRectangle(cornerRadius: 12).fill(categoryFilterMode && categoryFilter == category.category ? boxColor.opacity(0.16) : Color.AppPageBackground))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(categoryFilterMode && categoryFilter == category.category ? boxColor : Color.clear, lineWidth: 1.3))
                                .fixedSize(horizontal: false, vertical: true)
                                .contentShape(Rectangle())
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(category.category.wrappedName)
                                .accessibilityValue("\(category.amount) ، \(Int(category.percent * 100))٪")
                                .drawingGroup()
                                .onTapGesture {
                                    withAnimation(.easeInOut) {
                                        if !categoryFilterMode {
                                            selectedDate = nil
                                            categoryFilterMode = true
                                            categoryFilter = category.category
                                            chosenAmount = category.percent * total
                                            chosenName = category.category.wrappedName
                                        }
                                    }
                                }

                            }

                        }
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    init(date: Date, categoryFilter: Binding<Category?>?, categoryFilterMode: Binding<Bool>, selectedDate: Binding<Date?>?, chosenAmount: Binding<Double>, chosenName: Binding<String>, type: ChartTimeFrame, income: Bool) {
        self.date = date
        self.income = income
        _categoryFilter = categoryFilter ?? Binding.constant(nil)
        _categoryFilterMode = categoryFilterMode
        _selectedDate = selectedDate ?? Binding.constant(nil)
        _chosenName = chosenName
        _chosenAmount = chosenAmount

        // fetching categories

        _allCategories = FetchRequest<Category>(sortDescriptors: [], predicate: NSPredicate(format: "income = %d", income))

        // fetching transactions

        let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), date as CVarArg)
        let incomePredicate = NSPredicate(format: "income = %d", income)

        let endPredicate: NSPredicate

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = Sa7totWeekday.storedSelection.rawValue
        calendar.minimumDaysInFirstWeek = 4

        switch type {
        case .week:
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .weekOfYear) {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                let next = calendar.date(byAdding: .day, value: 7, to: date) ?? Date.now
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        case .month:
            let next = calendar.date(byAdding: .month, value: 1, to: date) ?? Date.now

            if next > Date.now {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        case .year:
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .year) {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                let next = calendar.date(byAdding: .year, value: 1, to: date) ?? Date.now
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        }

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [
            startPredicate,
            endPredicate,
            incomePredicate,
            StatisticsTransactionFilter.excludingTransfersPredicate()
        ])

        _transactions = FetchRequest<Transaction>(sortDescriptors: [], predicate: andPredicate)
    }
}

struct StatisticsCategoryListView: View {
    @FetchRequest private var allCategories: FetchedResults<Category>
    @FetchRequest private var transactions: FetchedResults<Transaction>

    let date: Date
    let type: ChartTimeFrame
    @Binding var categoryFilter: Category?
    @Binding var categoryFilterMode: Bool
    @Binding var selectedDate: Date?
    @Binding var chosenAmount: Double
    @Binding var chosenName: String

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!
    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true

    private var totalIncome: Double {
        transactions.filter { $0.income }.reduce(0) { $0 + $1.wrappedAmount }
    }

    private var totalExpense: Double {
        transactions.filter { !$0.income }.reduce(0) { $0 + $1.wrappedAmount }
    }

    private var categories: [PowerCategory] {
        let grouped = Dictionary(grouping: transactions) { $0.category }
        return allCategories.compactMap { category in
            let amount = grouped[category, default: []].reduce(0) { $0 + $1.wrappedAmount }
            guard amount > 0 else { return nil }
            let percent = StatisticsCombinedSeries.categoryPercentage(
                amount: amount,
                income: category.income,
                totalIncome: totalIncome,
                totalExpense: totalExpense
            )
            guard percent > 0 else { return nil }
            return PowerCategory(id: category.id ?? UUID(), category: category, percent: percent, amount: amount)
        }
        .sorted {
            if $0.category.income != $1.category.income {
                return $0.category.income
            }
            return $0.percent > $1.percent
        }
    }

    var body: some View {
        if categories.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Categorie")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.PrimaryText)
                    Spacer()
                }

                VStack(spacing: 0) {
                    ForEach(categories) { item in
                        let color = item.category.statisticsColor
                        let selected = categoryFilterMode && categoryFilter == item.category

                        VStack(spacing: 7) {
                            HStack(spacing: 10) {
                                CategoryIconView(descriptor: item.category.iconDescriptor, role: .category, tint: color, accessibilityLabel: item.category.wrappedName)
                                    .frame(width: 40, height: 40)

                                Text(item.category.wrappedName)
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .foregroundColor(Color.PrimaryText)
                                    .lineLimit(1)

                                Spacer(minLength: 4)

                                Text(StatisticsSummaryPresentation.amount(item.amount, currencyCode: currency, showCents: showCents))
                                    .font(.system(.body, design: .rounded).weight(.medium))
                                    .foregroundColor(Color.PrimaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)

                                if selected {
                                    Button {
                                        clearSelection()
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(.caption, design: .rounded).weight(.bold))
                                            .foregroundColor(color)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Cancella selezione categoria")
                                } else {
                                    Text("\(item.percent * 100, specifier: "%.0f")%")
                                        .font(.system(.caption, design: .rounded).weight(.semibold))
                                        .foregroundColor(color)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(color.opacity(0.18), in: Capsule())
                                }
                            }

                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.SubtitleText.opacity(0.16))
                                    Capsule().fill(color).frame(width: proxy.size.width * min(max(item.percent, 0), 1))
                                }
                            }
                            .frame(height: 4)
                            .padding(.leading, 50)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .opacity(categoryFilterMode && !selected ? 0.55 : 1)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(item.category.wrappedName)
                        .accessibilityValue("\(item.amount), \(Int(item.percent * 100))%")
                        .onTapGesture {
                            select(item)
                        }

                        if item.id != categories.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private func select(_ item: PowerCategory) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if categoryFilter == item.category {
                clearSelection()
            } else {
                selectedDate = nil
                categoryFilterMode = true
                categoryFilter = item.category
                chosenAmount = item.amount
                chosenName = item.category.wrappedName
            }
        }
    }

    private func clearSelection() {
        selectedDate = nil
        categoryFilterMode = false
        categoryFilter = nil
    }

    init(date: Date, categoryFilter: Binding<Category?>, categoryFilterMode: Binding<Bool>, selectedDate: Binding<Date?>, chosenAmount: Binding<Double>, chosenName: Binding<String>, type: ChartTimeFrame) {
        self.date = date
        self.type = type
        _categoryFilter = categoryFilter
        _categoryFilterMode = categoryFilterMode
        _selectedDate = selectedDate
        _chosenAmount = chosenAmount
        _chosenName = chosenName

        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = Sa7totWeekday.storedSelection.rawValue
        calendar.minimumDaysInFirstWeek = 4
        let next: Date
        switch type {
        case .week: next = calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .month: next = calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .year: next = calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
        let end = min(next, Date.now)
        let rangePredicate = NSCompoundPredicate(type: .and, subpredicates: [
            NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), date as CVarArg),
            NSPredicate(format: "%K < %@", #keyPath(Transaction.date), end as CVarArg),
            StatisticsTransactionFilter.excludingTransfersPredicate()
        ])
        _allCategories = FetchRequest<Category>(sortDescriptors: [SortDescriptor(\.name)], predicate: nil)
        _transactions = FetchRequest<Transaction>(sortDescriptors: [SortDescriptor(\.date, order: .reverse)], predicate: rangePredicate)
    }
}

struct FilteredCategoryInsightsView: View {
    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>

    var body: some View {
        VStack(spacing: 30) {
            if transactions.count == 0 {
                NoResultsView(fullscreen: false)
            }

            ListView(transactions: _transactions)
        }
        .frame(maxHeight: .infinity)
    }

    init(category: Category?, date: Date, type: ChartTimeFrame) {
        if let unwrappedCategory = category {
            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), date as CVarArg)
            let categoryPredicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.category), unwrappedCategory)
            let incomePredicate = NSPredicate(format: "income = %d", unwrappedCategory.income)

            let endPredicate: NSPredicate

            var calendar = Calendar(identifier: .gregorian)

            calendar.firstWeekday = Sa7totWeekday.storedSelection.rawValue
            calendar.minimumDaysInFirstWeek = 4

            switch type {
            case .week:
                if calendar.isDate(date, equalTo: Date.now, toGranularity: .weekOfYear) {
                    endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
                } else {
                    let next = calendar.date(byAdding: .day, value: 7, to: date) ?? Date.now
                    endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
                }
            case .month:
                if calendar.isDate(date, equalTo: Date.now, toGranularity: .month) {
                    endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
                } else {
                    let next = calendar.date(byAdding: .month, value: 1, to: date) ?? Date.now
                    endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
                }
            case .year:
                if calendar.isDate(date, equalTo: Date.now, toGranularity: .year) {
                    endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
                } else {
                    let next = calendar.date(byAdding: .year, value: 1, to: date) ?? Date.now
                    endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
                }
            }

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [
                startPredicate,
                endPredicate,
                categoryPredicate,
                incomePredicate,
                StatisticsTransactionFilter.excludingTransfersPredicate()
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
    }
}

struct FilteredDateInsightsView: View {
    @FetchRequest private var transactions: FetchedResults<Transaction>

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
                NoResultsView(fullscreen: false)
            }
            ForEach(transactions) { transaction in
                SingleTransactionView(transaction: transaction, showCents: showCents, currencySymbol: currencySymbol, currency: currency, swapTimeLabel: swapTimeLabel, future: false, showExpenseOrIncomeSign: showExpenseOrIncomeSign)
            }
        }
        .frame(maxHeight: .infinity)
    }

    init(date: Date, income: Bool) {
        let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), date as CVarArg)

        let endPredicate: NSPredicate

        let calendar = Calendar.current

        if calendar.isDate(date, equalTo: Date.now, toGranularity: .day) {
            endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
        } else {
            let next = calendar.date(byAdding: .day, value: 1, to: date) ?? Date.now
            endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
        }

        let incomePredicate = NSPredicate(format: "income = %d", income)

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [
            startPredicate,
            incomePredicate,
            endPredicate,
            StatisticsTransactionFilter.excludingTransfersPredicate()
        ])

        _transactions = FetchRequest<Transaction>(sortDescriptors: [
            SortDescriptor(\.date, order: .reverse)
        ], predicate: andPredicate)
    }
}

struct FilteredInsightsView: View {
    @SectionedFetchRequest<Date?, Transaction> private var transactions: SectionedFetchResults<Date?, Transaction>

    var body: some View {
        VStack(spacing: 30) {
            if transactions.count == 0 {
                NoResultsView(fullscreen: false)
            }

            ListView(transactions: _transactions)
        }
        .frame(maxHeight: .infinity)
    }

    init(startDate: Date, income: Bool? = nil, period: InsightsPeriod) {
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
            andPredicate = NSCompoundPredicate(type: .and, subpredicates: [
                startPredicate,
                endPredicate,
                incomePredicate,
                StatisticsTransactionFilter.excludingTransfersPredicate()
            ])

        } else {
            andPredicate = NSCompoundPredicate(type: .and, subpredicates: [
                startPredicate,
                endPredicate,
                StatisticsTransactionFilter.excludingTransfersPredicate()
            ])
        }

        _transactions = SectionedFetchRequest<Date?, Transaction>(sectionIdentifier: \.day, sortDescriptors: [
            SortDescriptor(\.day, order: .reverse),
            SortDescriptor(\.date, order: .reverse)
        ], predicate: andPredicate)
    }
}

struct SingleGraphView: View {
    @EnvironmentObject var dataController: DataController
    var date: Date
    let type: Int

    @Binding var categoryFilterMode: Bool
    @Binding var selectedDate: Date?

    @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var incomeTracking: Bool = true
    let language = Locale.current.languageCode

    var selectedDateString: String {
        if let unwrappedDate = selectedDate {
            let dateFormatter = DateFormatter()

            if type == 3 {
                dateFormatter.dateFormat = "MMM yyyy"
            } else {
                dateFormatter.dateFormat = "d MMM yyyy"
            }

            if language == "ru" {
                return dateFormatter.string(from: unwrappedDate)
            } else {
                return dateFormatter.string(from: unwrappedDate)
            }
        } else {
            return ""
        }
    }

    @State var selectedDateAmount: Double = 0

    var currencySymbol: String
    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!
    var showCents: Bool

    var dateString: String {
        StatisticsSummaryPresentation.periodRange(start: date, type: type)
    }

    private var summaryMetricLabel: String {
        if categoryFilterMode {
            return selectedCategoryName
        } else if selectedDate != nil {
            return selectedDateString
        }
        return StatisticsSummaryPresentation.averageLabel(type: type, incomeFiltering: incomeTracking, income: income)
    }

    private var summaryMetricAmount: Double {
        if categoryFilterMode {
            return selectedCategoryAmount
        } else if selectedDate != nil {
            return selectedDateAmount
        } else if incomeTracking {
            return incomeAverage
        }
        return average
    }

    var selectedCategoryName: String
    var selectedCategoryAmount: Double

    @Binding var income: Bool
    @Binding var incomeFiltering: Bool

    let totalIncome: Double
    let totalSpent: Double
    let totalNet: Double
    let netPositive: Bool
    let currentNet: Double
    let lastNet: Double
    let average: Double

    var incomeAverage: Double {
        let loaded = dataController.getInsights(type: type, date: date, income: income)
        return loaded.average
    }

    var percentageDifference: String {
        if lastNet == 0 {
            return ""
        }

        let percentage: Double = ((currentNet - lastNet) / abs(lastNet)) * 100

        let roundedPercentage = Int(ceil(percentage))

        if currentNet > lastNet {
            return "+\(roundedPercentage)%"
        } else {
            return "\(roundedPercentage)%"
        }
    }

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var fontSize: CGFloat {
        switch dynamicTypeSize {
        case .xSmall:
            return 14
        case .small:
            return 15
        case .medium:
            return 16
        case .large:
            return 17
        case .xLarge:
            return 19
        case .xxLarge:
            return 21
        case .xxxLarge:
            return 23
        default:
            return 23
        }
    }

    var showPercentage: Bool {
        let amountText = stringConverter(amount: totalNet)
        let supplementalText: String

        if categoryFilterMode {
            supplementalText = stringConverter(amount: selectedCategoryAmount)
        } else if selectedDate != nil {
            supplementalText = stringConverter(amount: selectedDateAmount)
        } else if incomeFiltering {
            supplementalText = stringConverter(amount: incomeAverage)
        } else {
            supplementalText = stringConverter(amount: average)
        }

        let totalWidth = amountText.widthOfRoundedString(size: UIFont.textStyleSize(.title1), weight: .medium)
        let averageWidth = supplementalText.widthOfRoundedString(size: UIFont.textStyleSize(.title1), weight: .medium)
        let percentageWidth = percentageDifference.widthOfRoundedString(size: UIFont.textStyleSize(.footnote), weight: .medium) + 10

        let screenWidth = UIScreen.main.bounds.width - 60

        return totalWidth + averageWidth + percentageWidth + 40 < screenWidth
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                VStack(spacing: 3) {
                    Text("Saldo netto")
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundColor(Color.SubtitleText)

                    Text(StatisticsSummaryPresentation.amount(totalNet, currencyCode: currency, showCents: showCents, negative: !netPositive))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.PrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 1) {
                    Text(summaryMetricLabel)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundColor(Color.SubtitleText)
                        .lineLimit(1)

                    Text(StatisticsSummaryPresentation.amount(summaryMetricAmount, currencyCode: currency, showCents: showCents))
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .foregroundColor(Color.PrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeIn(duration: 0.2)) {
                    selectedDate = nil
                }
            }

            HStack(spacing: 20) {
                StatisticsInlineTotalView(income: true, amount: totalIncome, currencyCode: currency, showCents: showCents)
                Rectangle()
                    .fill(Color.SubtitleText.opacity(0.35))
                    .frame(width: 1, height: 28)
                StatisticsInlineTotalView(income: false, amount: totalSpent, currencyCode: currency, showCents: showCents)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    func stringGenerator(amount: Double) -> String {
        StatisticsSummaryPresentation.amount(amount, currencyCode: currency, showCents: showCents)
    }

    func stringConverter(amount: Double) -> String {
        if showCents && amount < 100 {
            return currencySymbol + String(format: "%.2f", amount)
        } else {
            return currencySymbol + String(format: "%.0f", amount)
        }
    }

    init(showingDate: Date, date: Binding<Date?>?, mode: Binding<Bool>, categoryName: String, categoryAmount: Double, currencySymbol: String, showCents: Bool, dataController: DataController, income: Binding<Bool>, incomeFiltering: Binding<Bool>, type: Int) {
        _selectedDate = date ?? Binding.constant(nil)
        _categoryFilterMode = mode
        _income = income
        _incomeFiltering = incomeFiltering
        self.date = showingDate
        selectedCategoryName = categoryName
        selectedCategoryAmount = categoryAmount
        self.currencySymbol = currencySymbol
        self.showCents = showCents
        self.type = type

        let loaded = dataController.getInsightsSummary(type: type, date: showingDate)

        totalIncome = loaded.income
        totalSpent = loaded.spent
        netPositive = loaded.positive
        totalNet = loaded.net
        average = loaded.average

        if loaded.positive {
            currentNet = loaded.net
        } else {
            currentNet = -loaded.net
        }

        let lastDate: Date

        if type == 1 {
            lastDate = Calendar.current.date(byAdding: .day, value: -7, to: showingDate) ?? Date.now
        } else if type == 2 {
            lastDate = Calendar.current.date(byAdding: .month, value: -1, to: showingDate) ?? Date.now
        } else {
            lastDate = Calendar.current.date(byAdding: .year, value: -1, to: showingDate) ?? Date.now
        }

        let lastDateData = dataController.getInsightsSummary(type: type, date: lastDate)

        if lastDateData.positive {
            lastNet = lastDateData.net
        } else {
            lastNet = -lastDateData.net
        }
    }
}

struct StatisticsPeriodNavigationRow: View {
    let periodLabel: String
    let canMoveBackward: Bool
    let canMoveForward: Bool
    let backwardAction: () -> Void
    let forwardAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if canMoveBackward {
                    SwipeArrowView(left: true, swipeString: "", changeTime: true, action: backwardAction)
                } else {
                    SwipeArrowView(left: true, swipeString: "", changeTime: false, isEnabled: false)
                }
            }
            .frame(width: 52, height: 48)

            Spacer(minLength: 0)

            Text(periodLabel)
                .font(.system(.title3, design: .rounded).weight(.medium))
                .foregroundColor(Color.PrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Group {
                if canMoveForward {
                    SwipeArrowView(left: false, swipeString: "", changeTime: true, action: forwardAction)
                } else {
                    SwipeArrowView(left: false, swipeString: "", changeTime: false, isEnabled: false)
                }
            }
            .frame(width: 52, height: 48)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.horizontal, 30)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigazione periodo")
        .accessibilityValue(periodLabel)
    }
}

struct StatisticsInlineTotalView: View {
    let income: Bool
    let amount: Double
    let currencyCode: String
    let showCents: Bool

    private var accent: Color { income ? Color.IncomeGreen : Color.AlertRed }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(income ? "Entrate" : "Spese")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundColor(accent)
            }

            Text(StatisticsSummaryPresentation.amount(amount, currencyCode: currencyCode, showCents: showCents))
                .font(.system(.title2, design: .rounded).weight(.medium))
                .foregroundColor(Color.PrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(income ? "Entrate" : "Spese")
        .accessibilityValue(StatisticsSummaryPresentation.amount(amount, currencyCode: currencyCode, showCents: showCents))
    }
}

struct StatisticsCombinedChartView: View {
    let buckets: [StatisticsCombinedBucket]
    let period: InsightsPeriod
    @Binding var selectedDate: Date?
    @Binding var categoryFilterMode: Bool
    @Binding var selectedDateAmount: Double

    private let chartHeight: CGFloat = 180

    private var maximum: Double {
        max(buckets.flatMap { [$0.income, $0.expense] }.max() ?? 0, 1)
    }

    private var chartMaximum: Double {
        max(10, ceil(maximum * 1.1 / 10) * 10)
    }

    private var title: String {
        switch period {
        case .week: return "Andamento giornaliero"
        case .month: return "Andamento giornaliero"
        case .year: return "Andamento mensile"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.PrimaryText)

                Spacer()

                HStack(spacing: 10) {
                    StatisticsChartLegend(color: Color.IncomeGreen, title: "Entrate")
                    StatisticsChartLegend(color: Color.AlertRed, title: "Spese")
                }
            }

            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading) {
                        Text(getMaxText(maxi: Int(chartMaximum)))
                        Spacer()
                        Text("0")
                    }
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
                    .frame(width: 28, height: chartHeight, alignment: .leading)

                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(buckets) { bucket in
                            VStack(spacing: 5) {
                                HStack(alignment: .bottom, spacing: 2) {
                                    StatisticsChartBar(value: bucket.income, maximum: chartMaximum, color: Color.IncomeGreen, height: chartHeight)
                                    StatisticsChartBar(value: bucket.expense, maximum: chartMaximum, color: Color.AlertRed, height: chartHeight)
                                }
                                .frame(height: chartHeight)

                                Text(bucketLabel(bucket.date))
                                    .font(.system(.caption2, design: .rounded).weight(.medium))
                                    .foregroundColor(Color.SubtitleText)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .opacity(bucket.date > Date.now ? 0.3 : 1)
                            .allowsHitTesting(bucket.date <= Date.now)
                            .contentShape(Rectangle())
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(bucketAccessibilityLabel(bucket.date))
                            .accessibilityValue("Entrate \(bucket.income), Spese \(bucket.expense)")
                            .onTapGesture {
                                withAnimation(.easeIn(duration: 0.2)) {
                                    if selectedDate == bucket.date {
                                        selectedDate = nil
                                        categoryFilterMode = false
                                    } else {
                                        selectedDate = bucket.date
                                        categoryFilterMode = false
                                        selectedDateAmount = bucket.income + bucket.expense
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: max(0, proxy.size.width - 36), height: chartHeight)
                }
            }
            .frame(height: chartHeight + 24)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func bucketLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = StatisticsSummaryPresentation.italianLocale
        formatter.dateFormat = period == .year ? "MMM" : "EEE"
        return formatter.string(from: date).lowercased().prefix(period == .year ? 3 : 3).description
    }

    private func bucketAccessibilityLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = StatisticsSummaryPresentation.italianLocale
        formatter.dateFormat = period == .year ? "MMMM yyyy" : "d MMMM"
        return formatter.string(from: date)
    }
}

struct StatisticsChartLegend: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(title)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Color.SubtitleText)
        }
    }
}

struct StatisticsChartBar: View {
    let value: Double
    let maximum: Double
    let color: Color
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color)
            .frame(maxWidth: .infinity)
            .frame(height: max(value == 0 ? 0 : 4, height * value / maximum), alignment: .bottom)
    }
}

struct WeekGraphView: View {
    @EnvironmentObject var dataController: DataController

    private var didSave = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
    @State private var refreshID = UUID()

    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.day)
    ]) private var transactions: FetchedResults<Transaction>

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true

    @State var categoryFilterMode = false
    @State var categoryFilter: Category?

    @State var selectedDate: Date?

    var startOfCurrentWeek: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = Sa7totWeekday.storedSelection.rawValue
        calendar.minimumDaysInFirstWeek = 4

        let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)

        return calendar.date(from: dateComponents) ?? Date.now
    }

    // start of week of final transaction
    var startOfLastWeek: Date {
        if transactions.isEmpty {
            return Date.now
        } else {
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = Sa7totWeekday.storedSelection.rawValue
            calendar.minimumDaysInFirstWeek = 4

            if let date = transactions[0].day {
                let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)

                return calendar.date(from: dateComponents) ?? Date.now
            } else {
                return Date.now
            }
        }
    }

    var swipeStrings: (backward: String, forward: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM"

        let calendar = Calendar.current

        let startOfLastWeek = calendar.date(byAdding: .day, value: -7, to: showingWeek) ?? Date.now
        let startOfNextWeek = calendar.date(byAdding: .day, value: 7, to: showingWeek) ?? Date.now

        return (dateFormatter.string(from: startOfLastWeek), dateFormatter.string(from: startOfNextWeek))
    }

    @State private var offset: CGFloat = 0
    @State private var changeDate: Bool = false
    @GestureState var isDragging = false
    var changeTime: Bool {
        if offset < -(UIScreen.main.bounds.width * 0.25) && showingWeek != startOfCurrentWeek {
            return true
        } else if offset > (UIScreen.main.bounds.width * 0.25) && showingWeek != startOfLastWeek {
            return true
        } else {
            return false
        }
//
//        return abs(offset) > UIScreen.main.bounds.width * 0.3
    }

    @State var showingWeek = Date.now

    @State private var refreshID1 = UUID()

    @State var chosenCategoryName = ""
    @State var chosenCategoryAmount = 0.0

    @AppStorage("insightsViewIncomeFiltering", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var income: Bool = true
    @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var incomeTracking: Bool = true

//    @Environment(\.dynamicTypeMultiplier) var multiplier

    @State var incomeFiltering: Bool = false

    private var combinedBuckets: [StatisticsCombinedBucket] {
        let incomeData = dataController.getInsights(type: 1, date: showingWeek, income: true)
        let expenseData = dataController.getInsights(type: 1, date: showingWeek, income: false)
        return StatisticsCombinedSeries.buckets(dates: incomeData.dates, income: incomeData.dateDictionary, expense: expenseData.dateDictionary)
    }

    var body: some View {
        VStack {
            StatisticsPeriodNavigationRow(
                periodLabel: StatisticsSummaryPresentation.periodRange(start: showingWeek, type: 1),
                canMoveBackward: StatisticsPeriodNavigation.canMoveBackward(current: showingWeek, oldest: startOfLastWeek),
                canMoveForward: StatisticsPeriodNavigation.canMoveForward(current: showingWeek, newest: startOfCurrentWeek),
                backwardAction: {
                    withAnimation { showingWeek = Calendar.current.date(byAdding: .day, value: -7, to: showingWeek) ?? showingWeek }
                },
                forwardAction: {
                    withAnimation { showingWeek = Calendar.current.date(byAdding: .day, value: 7, to: showingWeek) ?? showingWeek }
                }
            )
            .padding(.bottom, 16)

            VStack(spacing: 18) {
                ZStack(alignment: .top) {
                    VStack(spacing: 18) {
                        SingleGraphView(showingDate: showingWeek, date: $selectedDate, mode: $categoryFilterMode, categoryName: chosenCategoryName, categoryAmount: chosenCategoryAmount, currencySymbol: currencySymbol, showCents: showCents, dataController: dataController, income: $income, incomeFiltering: $incomeFiltering, type: 1)
                        StatisticsCombinedChartView(buckets: combinedBuckets, period: .week, selectedDate: $selectedDate, categoryFilterMode: $categoryFilterMode, selectedDateAmount: $chosenCategoryAmount)
                    }
                        .drawingGroup()
                        .id(refreshID)
                        .onAppear {
                            showingWeek = startOfCurrentWeek
                        }
                        .offset(x: offset)

                }
                .contentShape(Rectangle())
                .padding(.horizontal, 30)
                .simultaneousGesture(
                    DragGesture()
                        .updating($isDragging, body: { _, state, _ in
                            state = true
                        })
                        .onChanged { value in
                            withAnimation {
                                if value.translation.width < 0, showingWeek != startOfCurrentWeek {
                                    offset = value.translation.width * 0.9
                                } else if value.translation.width < 0, showingWeek == startOfCurrentWeek {
                                    offset = value.translation.width * 0.5
                                } else if value.translation.width > 0, showingWeek != startOfLastWeek {
                                    offset = value.translation.width * 0.9
                                } else if value.translation.width > 0, showingWeek == startOfLastWeek {
                                    offset = value.translation.width * 0.5
                                }
                            }
                        }.onEnded { _ in
                            if changeTime {
                                if offset < 0, showingWeek != startOfCurrentWeek {
                                    changeDate = true

                                    offset = UIScreen.main.bounds.width

                                    showingWeek = Calendar.current.date(byAdding: .day, value: 7, to: showingWeek) ?? Date.now

                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        offset = 0
                                    }
                                } else if offset > 0, showingWeek != startOfLastWeek {
                                    changeDate = true

                                    offset = -UIScreen.main.bounds.width

                                    showingWeek = Calendar.current.date(byAdding: .day, value: -7, to: showingWeek) ?? Date.now

                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        offset = 0
                                    }
                                }

                                withAnimation(.easeInOut(duration: 0.3)) {
                                    offset = 0
                                }

                                changeDate = false
                            }
                        }
                )
                .onChange(of: changeTime) { _ in
                    if changeTime {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onChange(of: isDragging) { _ in
                    if !isDragging && !changeDate {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            offset = 0
                        }
                    }
                }
                .animation(.easeInOut, value: changeTime)
                .onChange(of: showingWeek) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                    refreshID1 = UUID()
                }
                .onChange(of: income) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .onChange(of: incomeFiltering) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .padding(.bottom, incomeFiltering ? 5 : 10)

                Group {
                    if selectedDate == nil {
                        StatisticsCategoryListView(date: showingWeek, categoryFilter: $categoryFilter, categoryFilterMode: $categoryFilterMode, selectedDate: $selectedDate, chosenAmount: $chosenCategoryAmount, chosenName: $chosenCategoryName, type: .week)
                            .padding(.horizontal, 30)
                            .padding(.bottom, 70)
                            .id(refreshID1)

                        if categoryFilterMode {
                            FilteredCategoryInsightsView(category: categoryFilter, date: showingWeek, type: .week)
                                .padding(.bottom, 70)
                                .padding(.horizontal, 20)
                        }
                    } else {
                        FilteredInsightsView(startDate: selectedDate ?? Date.now, period: .week)
                            .padding(.bottom, 70)
                            .padding(.horizontal, 20)
                    }
                }
                .onTapGesture {
                    selectedDate = nil
                    categoryFilterMode = false
                }
            }
        }
        .onReceive(self.didSave) { _ in
            self.refreshID = UUID()
            self.refreshID1 = UUID()
        }
    }
}

struct AverageLineView: View {
    var getMax: Int
    var average: Double

//    @AppStorage("animated", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var animated: Bool = true
//    @State var showLine: Bool = false
//    @State var offset: CGFloat

//    var calculatedOffset: CGFloat {
//        return getOffset(maxi: getMax, average: average)
//    }

    var body: some View {
        HStack(spacing: 2) {
            PencilView(text: getAverageText(average: average))

            Line()
                .stroke(Color.SubtitleText, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5]))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
//        .opacity(showLine ? 1 : 0)
        .offset(y: getOffset(maxi: getMax, average: average))
        .opacity((average / Double(getMax)) < 0.1 || (average / Double(getMax)) > 0.9 ? 0 : 1)
//        .onAppear {
//            DispatchQueue.main.sync {
//                withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.8)) {
//                    print(calculatedOffset)
//                    offset = calculatedOffset
//                }
//            }
//        }
//        .onChange(of: showLine) { newValue in
//            if newValue {
//                DispatchQueue.main.asyncAfter(deadline: .now()) {
//                    if !animated {
//                        offset = calculatedOffset
//                    } else {
//                        
//                    }
//                }
//            }
//        }
//        .onChange(of: calculatedOffset) { newValue in
//            print(calculatedOffset)
//            if newValue != 0 {
//                if showLine {
//                    if !animated {
//                        offset = calculatedOffset
//                    } else {
//                        withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.8)) {
//                            offset = calculatedOffset
//                        }
//                    }
//                }
//            }
//        }

    }
}

struct SingleWeekBarGraphView: View {
    @Binding var selectedDate: Date?
    @Binding var categoryFilterMode: Bool
    @Binding var selectedDateAmount: Double

    @State private var refreshID = UUID()

    var daysOfWeek = [Date]()

    var dayDictionary = [Date: Double]()

    var max: Double = 0
    var weekTotal: Double = 0
    var weekAverage: Double = 0
    var actualDays: Int = 0

    var getMax: Int {
        let maximum = max * 1.1

        return Int(ceil(maximum / 10) * 10)
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 8) {
                // axes
                VStack(alignment: .leading) {
                    Text(getMaxText(maxi: getMax))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                    Spacer()

                    Text("0")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                }
                .frame(height: barHeight)
                .padding(.trailing, 3)

                // bars
                HStack(spacing: 7) {
                    ForEach(daysOfWeek, id: \.self) { day in
                        VStack(spacing: 5) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.AppSecondarySurface)
                                    .frame(height: barHeight)

                                AnimatedBarGraph(index: daysOfWeek.firstIndex(of: day) ?? 0)
                                    .frame(height: getBarHeight(point: dayDictionary[day] ?? 0, maxi: getMax))
                                    .opacity(selectedDate == nil ? 1 : (selectedDate == day ? 1 : 0.4))
                            }

                            Text(getWeekday(day: day).prefix(1))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Color.SubtitleText)
                        }
                        .opacity(day > Date.now ? 0.3 : 1)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(!(day > Date.now))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(getWeekday(day: day))
                        .accessibilityValue(String(format: "%.0f", dayDictionary[day] ?? 0))
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.2)) {
                                if selectedDate == day {
                                    selectedDate = nil
                                    categoryFilterMode = false
                                } else {
                                    selectedDate = day
                                    categoryFilterMode = false
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            // average line
            AverageLineView(getMax: getMax, average: weekAverage)
                .opacity(actualDays <= 1 ? 0 : 1)
                .id(refreshID)

        }
        .onChange(of: selectedDate) { _ in
            selectedDateAmount = dayDictionary[selectedDate ?? Date.now] ?? 0.0
            refreshID = UUID()
        }
    }

    func getWeekday(day: Date) -> String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "EEE"

        return dateFormatter.string(from: day)
    }

    init(week: Date, date: Binding<Date?>?, mode: Binding<Bool>, amount: Binding<Double>, dataController: DataController, income: Bool) {
        _selectedDate = date ?? Binding.constant(nil)
        _categoryFilterMode = mode
        _selectedDateAmount = amount

        let loaded = dataController.getInsights(type: 1, date: week, income: income)

        daysOfWeek = loaded.dates
        dayDictionary = loaded.dateDictionary
        self.max = loaded.maximum
        weekTotal = loaded.amount
        weekAverage = loaded.average
        actualDays = loaded.numberOfDays
    }
}

struct MonthGraphView: View {
    @EnvironmentObject var dataController: DataController
    private var didSave = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
    @State private var refreshID = UUID()

    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.day)
    ]) private var transactions: FetchedResults<Transaction>

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true

    @State var categoryFilterMode = false
    @State var categoryFilter: Category?

    @State var selectedDate: Date?

    var startOfCurrentMonth: Date {
        Sa7totCalendarSettings.startOfMonth(for: Date.now)
    }

    // start of month of the earliest transaction
    var startOfLastMonth: Date {
        if transactions.isEmpty {
            return Date.now
        } else {
            let date = transactions[0].day ?? Date.now

            return Sa7totCalendarSettings.startOfMonth(for: date)
        }
    }

    var swipeStrings: (backward: String, forward: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM yy"

        let calendar = Calendar.current

        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: showingMonth) ?? Date.now
        let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: showingMonth) ?? Date.now

        return (dateFormatter.string(from: startOfLastMonth), dateFormatter.string(from: startOfNextMonth))
    }

    @State private var offset: CGFloat = 0
    @State private var changeDate: Bool = false
    @GestureState var isDragging = false
    var changeTime: Bool {
        if offset < -(UIScreen.main.bounds.width * 0.25) && showingMonth != startOfCurrentMonth {
            return true
        } else if offset > (UIScreen.main.bounds.width * 0.25) && showingMonth != startOfLastMonth {
            return true
        } else {
            return false
        }
//
//        return abs(offset) > UIScreen.main.bounds.width * 0.3
    }

    @State var showingMonth = Date.now

    @State private var refreshID1 = UUID()

    @State var chosenCategoryName = ""
    @State var chosenCategoryAmount = 0.0

    @AppStorage("insightsViewIncomeFiltering", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var income: Bool = true
    @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var incomeTracking: Bool = true

//    @Environment(\.dynamicTypeMultiplier) var multiplier

    @State var incomeFiltering: Bool = false

    private var combinedBuckets: [StatisticsCombinedBucket] {
        let incomeData = dataController.getInsights(type: 2, date: showingMonth, income: true)
        let expenseData = dataController.getInsights(type: 2, date: showingMonth, income: false)
        return StatisticsCombinedSeries.buckets(dates: incomeData.dates, income: incomeData.dateDictionary, expense: expenseData.dateDictionary)
    }

    var body: some View {
        VStack {
            StatisticsPeriodNavigationRow(
                periodLabel: StatisticsSummaryPresentation.periodRange(start: showingMonth, type: 2),
                canMoveBackward: StatisticsPeriodNavigation.canMoveBackward(current: showingMonth, oldest: startOfLastMonth),
                canMoveForward: StatisticsPeriodNavigation.canMoveForward(current: showingMonth, newest: startOfCurrentMonth),
                backwardAction: {
                    withAnimation { showingMonth = Calendar.current.date(byAdding: .month, value: -1, to: showingMonth) ?? showingMonth }
                },
                forwardAction: {
                    withAnimation { showingMonth = Calendar.current.date(byAdding: .month, value: 1, to: showingMonth) ?? showingMonth }
                }
            )
            .padding(.bottom, 16)

            VStack(spacing: 18) {
                ZStack(alignment: .top) {
                    VStack(spacing: 18) {
                        SingleGraphView(showingDate: showingMonth, date: $selectedDate, mode: $categoryFilterMode, categoryName: chosenCategoryName, categoryAmount: chosenCategoryAmount, currencySymbol: currencySymbol, showCents: showCents, dataController: dataController, income: $income, incomeFiltering: $incomeFiltering, type: 2)
                        StatisticsCombinedChartView(buckets: combinedBuckets, period: .month, selectedDate: $selectedDate, categoryFilterMode: $categoryFilterMode, selectedDateAmount: $chosenCategoryAmount)
                    }
                        .drawingGroup()
                        .id(refreshID)
                        .onAppear {
                            showingMonth = startOfCurrentMonth
                        }
                        .offset(x: offset)

                }
                .contentShape(Rectangle())
                .padding(.horizontal, 30)
                .simultaneousGesture(
                    DragGesture()
                        .updating($isDragging, body: { _, state, _ in
                            state = true
                        })
                        .onChanged { value in
                            withAnimation {
                                if value.translation.width < 0, showingMonth != startOfCurrentMonth {
                                    offset = value.translation.width * 0.9
                                } else if value.translation.width < 0, showingMonth == startOfCurrentMonth {
                                    offset = value.translation.width * 0.5
                                } else if value.translation.width > 0, showingMonth != startOfLastMonth {
                                    offset = value.translation.width * 0.9
                                } else if value.translation.width > 0, showingMonth == startOfLastMonth {
                                    offset = value.translation.width * 0.5
                                }
                            }
                        }.onEnded { _ in
                            if changeTime {
                                if offset < 0, showingMonth != startOfCurrentMonth {
                                    changeDate = true

                                    offset = UIScreen.main.bounds.width

                                    showingMonth = Calendar.current.date(byAdding: .month, value: 1, to: showingMonth) ?? Date.now

                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        offset = 0
                                    }
                                } else if offset > 0, showingMonth != startOfLastMonth {
                                    changeDate = true

                                    offset = -UIScreen.main.bounds.width

                                    showingMonth = Calendar.current.date(byAdding: .month, value: -1, to: showingMonth) ?? Date.now

                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        offset = 0
                                    }
                                }

                                withAnimation(.easeInOut(duration: 0.3)) {
                                    offset = 0
                                }

                                changeDate = false
                            }
                        }
                )
                .onChange(of: changeTime) { _ in
                    if changeTime {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onChange(of: isDragging) { _ in
                    if !isDragging && !changeDate {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            offset = 0
                        }
                    }
                }
                .animation(.easeInOut, value: changeTime)
                .onChange(of: showingMonth) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                    refreshID1 = UUID()
                }
                .onChange(of: income) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .onChange(of: incomeFiltering) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .padding(.bottom, incomeFiltering ? 5 : 20)
                
                Group {
                    if selectedDate == nil {
                        StatisticsCategoryListView(date: showingMonth, categoryFilter: $categoryFilter, categoryFilterMode: $categoryFilterMode, selectedDate: $selectedDate, chosenAmount: $chosenCategoryAmount, chosenName: $chosenCategoryName, type: .month)
                            .padding(.horizontal, 30)
                            .padding(.bottom, 70)
                            .id(refreshID1)

                        if categoryFilterMode {
                            FilteredCategoryInsightsView(category: categoryFilter, date: showingMonth, type: .month)
                                .padding(.bottom, 70)
                                .padding(.horizontal, 20)
                        }
                    } else {
                        FilteredInsightsView(startDate: selectedDate ?? Date.now, period: .month)
                            .padding(.bottom, 70)
                            .padding(.horizontal, 20)
                    }
                }

//                Group {
//                    if !incomeFiltering {
//                        FilteredInsightsView(startDate: showingMonth, type: 2)
//                            .padding(.bottom, 70)
//                    } else {
//                        if selectedDate != nil {
//                            FilteredDateInsightsView(date: selectedDate ?? Date.now, income: income)
//                                .padding(.bottom, 70)
//
//                        } else if categoryFilterMode {
//                            FilteredCategoryInsightsView(category: categoryFilter, date: showingMonth, type: .month)
//                                .padding(.bottom, 70)
//                        } else {
//                            FilteredInsightsView(startDate: showingMonth, income: income, type: 2)
//                                .padding(.bottom, 70)
//                        }
//                    }
//                }
//                .padding(.horizontal, 20)
//                .onTapGesture {
//                    selectedDate = nil
//                    categoryFilterMode = false
//                }
            }
        }
        .onReceive(self.didSave) { _ in
            self.refreshID = UUID()
            self.refreshID1 = UUID()
        }
    }
}

struct SingleMonthBarGraphView: View {
    @Binding var selectedDate: Date?
    @Binding var categoryFilterMode: Bool
    @Binding var selectedDateAmount: Double

    var daysOfMonth = [Date]()

    var dayDictionary = [Date: Double]()

    var max: Double = 0
    var monthTotal: Double = 0
    var monthAverage: Double = 0
    var actualDays: Int = 0

    var getMax: Int {
        let maximum = max * 1.1

        return Int(ceil(maximum / 10) * 10)
    }

    let numberArray = [1, 8, 15, 22, 29]

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 3) {
                // axes
                VStack(alignment: .leading) {
                    Text(getMaxText(maxi: getMax))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                    Spacer()

                    Text("0")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                }
                .frame(height: barHeight)
                .padding(.trailing, 3)

                // bars
                HStack(alignment: .top, spacing: 2) {
                    ForEach(daysOfMonth, id: \.self) { day in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.AppSecondarySurface)
                                .frame(height: barHeight)
                                .zIndex(0)

                            AnimatedBarGraph(index: daysOfMonth.firstIndex(of: day) ?? 0)
                                .frame(height: getBarHeight(point: dayDictionary[day] ?? 0, maxi: getMax))
                                .opacity(selectedDate == nil ? 1 : (selectedDate == day ? 1 : 0.4))
                                .zIndex(0)
                                .overlay(alignment: .bottom) {
                                    if numberArray.contains((daysOfMonth.firstIndex(of: day) ?? -1) + 1) {
                                        Text("\((daysOfMonth.firstIndex(of: day) ?? -1) + 1)")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundColor(Color.SubtitleText)
                                            .frame(width: 20, alignment: .center)
                                            .offset(y: 20)
                                    }
                                }
                        }
                        .padding(.bottom, 22)
                        .opacity(day > Date.now ? 0.3 : 1)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(!(day > Date.now))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Giorno \((daysOfMonth.firstIndex(of: day) ?? 0) + 1)")
                        .accessibilityValue(String(format: "%.0f", dayDictionary[day] ?? 0))
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.2)) {
                                if selectedDate == day {
                                    selectedDate = nil
                                    categoryFilterMode = false
                                } else {
                                    selectedDate = day
                                    categoryFilterMode = false
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

            }
            .frame(maxWidth: .infinity)

            //                .frame(maxHeight: .infinity)

            // average line

            AverageLineView(getMax: getMax, average: monthAverage)
                .opacity(actualDays <= 1 ? 0 : 1)

        }
        .onChange(of: selectedDate) { _ in
            selectedDateAmount = dayDictionary[selectedDate ?? Date.now] ?? 0.0
        }
    }

    init(month: Date, date: Binding<Date?>?, mode: Binding<Bool>, amount: Binding<Double>, dataController: DataController, income: Bool) {
        _selectedDate = date ?? Binding.constant(nil)
        _categoryFilterMode = mode
        _selectedDateAmount = amount

        let loaded = dataController.getInsights(type: 2, date: month, income: income)

        daysOfMonth = loaded.dates
        dayDictionary = loaded.dateDictionary
        self.max = loaded.maximum
        monthTotal = loaded.amount
        monthAverage = loaded.average
        actualDays = loaded.numberOfDays
    }
}

struct YearGraphView: View {
    @EnvironmentObject var dataController: DataController
    private var didSave = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
    @State private var refreshID = UUID()

    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.day)
    ]) private var transactions: FetchedResults<Transaction>

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true

    @State var categoryFilterMode = false
    @State var categoryFilter: Category?

    @State var selectedDate: Date?

    var startOfCurrentYear: Date {
        let calendar = Calendar(identifier: .gregorian)

        let dateComponents = calendar.dateComponents([.year], from: Date.now)

        return calendar.date(from: dateComponents) ?? Date.now
    }

    var startOfLastYear: Date {
        if transactions.isEmpty {
            return Date.now
        } else {
            let calendar = Calendar(identifier: .gregorian)

            let date = transactions[0].day ?? Date.now

            let dateComponents = calendar.dateComponents([.year], from: date)

            return calendar.date(from: dateComponents) ?? Date.now
        }
    }

    var swipeStrings: (backward: String, forward: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy"

        let calendar = Calendar.current

        let startOfLastYear = calendar.date(byAdding: .year, value: -1, to: showingYear) ?? Date.now
        let startOfNextYear = calendar.date(byAdding: .year, value: 1, to: showingYear) ?? Date.now

        return (dateFormatter.string(from: startOfLastYear), dateFormatter.string(from: startOfNextYear))
    }

    @State private var offset: CGFloat = 0
    @State private var changeDate: Bool = false
    @GestureState var isDragging = false
    var changeTime: Bool {
        if offset < -(UIScreen.main.bounds.width * 0.25) && showingYear != startOfCurrentYear {
            return true
        } else if offset > (UIScreen.main.bounds.width * 0.25) && showingYear != startOfLastYear {
            return true
        } else {
            return false
        }
//
//        return abs(offset) > UIScreen.main.bounds.width * 0.3
    }

    @State var showingYear = Date.now

    @State private var refreshID1 = UUID()

    @State var chosenCategoryName = ""
    @State var chosenCategoryAmount = 0.0

    @AppStorage("insightsViewIncomeFiltering", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var income: Bool = true
    @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var incomeTracking: Bool = true
//
//    @Environment(\.dynamicTypeMultiplier) var multiplier

    @State var incomeFiltering: Bool = false

    private var combinedBuckets: [StatisticsCombinedBucket] {
        let incomeData = dataController.getInsights(type: 3, date: showingYear, income: true)
        let expenseData = dataController.getInsights(type: 3, date: showingYear, income: false)
        return StatisticsCombinedSeries.buckets(dates: incomeData.dates, income: incomeData.dateDictionary, expense: expenseData.dateDictionary)
    }

    var body: some View {
        VStack {
            StatisticsPeriodNavigationRow(
                periodLabel: StatisticsSummaryPresentation.periodRange(start: showingYear, type: 3),
                canMoveBackward: StatisticsPeriodNavigation.canMoveBackward(current: showingYear, oldest: startOfLastYear),
                canMoveForward: StatisticsPeriodNavigation.canMoveForward(current: showingYear, newest: startOfCurrentYear),
                backwardAction: {
                    withAnimation { showingYear = Calendar.current.date(byAdding: .year, value: -1, to: showingYear) ?? showingYear }
                },
                forwardAction: {
                    withAnimation { showingYear = Calendar.current.date(byAdding: .year, value: 1, to: showingYear) ?? showingYear }
                }
            )
            .padding(.bottom, 16)

            VStack(spacing: 18) {
                ZStack(alignment: .top) {
                    VStack(spacing: 18) {
                        SingleGraphView(showingDate: showingYear, date: $selectedDate, mode: $categoryFilterMode, categoryName: chosenCategoryName, categoryAmount: chosenCategoryAmount, currencySymbol: currencySymbol, showCents: showCents, dataController: dataController, income: $income, incomeFiltering: $incomeFiltering, type: 3)
                        StatisticsCombinedChartView(buckets: combinedBuckets, period: .year, selectedDate: $selectedDate, categoryFilterMode: $categoryFilterMode, selectedDateAmount: $chosenCategoryAmount)
                    }
                        .drawingGroup()
                        .id(refreshID)
                        .onAppear {
                            showingYear = startOfCurrentYear
                        }
                        .offset(x: offset)

                }
                .contentShape(Rectangle())
                .padding(.horizontal, 30)
                .simultaneousGesture(
                    DragGesture()
                        .updating($isDragging, body: { _, state, _ in
                            state = true
                        })
                        .onChanged { value in
                            withAnimation {
                                if value.translation.width < 0, showingYear != startOfCurrentYear {
                                    offset = value.translation.width * 0.9
                                } else if value.translation.width < 0, showingYear == startOfCurrentYear {
                                    offset = value.translation.width * 0.5
                                } else if value.translation.width > 0, showingYear != startOfLastYear {
                                    offset = value.translation.width * 0.9
                                } else if value.translation.width > 0, showingYear == startOfLastYear {
                                    offset = value.translation.width * 0.5
                                }
                            }
                        }.onEnded { _ in
                            if changeTime {
                                if offset < 0, showingYear != startOfCurrentYear {
                                    changeDate = true

                                    offset = UIScreen.main.bounds.width

                                    showingYear = Calendar.current.date(byAdding: .year, value: 1, to: showingYear) ?? Date.now

                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        offset = 0
                                    }
                                } else if offset > 0, showingYear != startOfLastYear {
                                    changeDate = true

                                    offset = -UIScreen.main.bounds.width

                                    showingYear = Calendar.current.date(byAdding: .year, value: -1, to: showingYear) ?? Date.now

                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        offset = 0
                                    }
                                }

                                withAnimation(.easeInOut(duration: 0.3)) {
                                    offset = 0
                                }

                                changeDate = false
                            }
                        }
                )
                .onChange(of: changeTime) { _ in
                    if changeTime {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onChange(of: isDragging) { _ in
                    if !isDragging && !changeDate {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            offset = 0
                        }
                    }
                }
                .animation(.easeInOut, value: changeTime)
                .onChange(of: showingYear) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                    refreshID1 = UUID()
                }
                .onChange(of: income) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .onChange(of: incomeFiltering) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .padding(.bottom, incomeFiltering ? 5 : 20)

                Group {
                    if selectedDate == nil {
                        StatisticsCategoryListView(date: showingYear, categoryFilter: $categoryFilter, categoryFilterMode: $categoryFilterMode, selectedDate: $selectedDate, chosenAmount: $chosenCategoryAmount, chosenName: $chosenCategoryName, type: .year)
                            .padding(.horizontal, 30)
                            .padding(.bottom, 70)
                            .id(refreshID1)

                        if categoryFilterMode {
                            FilteredCategoryInsightsView(category: categoryFilter, date: showingYear, type: .year)
                                .padding(.bottom, 70)
                                .padding(.horizontal, 20)
                        }
                    } else {
                        FilteredInsightsView(startDate: selectedDate ?? Date.now, period: .month)
                            .padding(.bottom, 70)
                            .padding(.horizontal, 20)
                    }
                }
            }
        }
        .onReceive(self.didSave) { _ in
            self.refreshID = UUID()
            self.refreshID1 = UUID()
        }
    }
}

struct SingleYearBarGraphView: View {
    @Binding var selectedDate: Date?
    @Binding var categoryFilterMode: Bool
    @Binding var selectedDateAmount: Double

    var monthsOfYear = [Date]()

    var monthDictionary = [Date: Double]()

    var max: Double = 0

    var getMax: Int {
        let maximum = max * 1.1

        return Int(ceil(maximum / 10) * 10)
    }

    var yearTotal: Double = 0
    var yearAverage: Double = 0
    var actualMonths: Int = 0
    var pastYearTotal: Double = 0

    let numberArray = [1, 4, 7, 10]
    let monthNames: [Int: String] = [1: "Jan", 4: "Apr", 7: "Jul", 10: "Oct"]

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 3) {
                // axes
                VStack(alignment: .leading) {
                    Text(getMaxText(maxi: getMax))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                    Spacer()

                    Text("0")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                }
                .frame(height: barHeight)
                .padding(.trailing, 3)

                // bars
                HStack(alignment: .top, spacing: 4) {
                    ForEach(monthsOfYear, id: \.self) { month in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.AppSecondarySurface)
                                .frame(height: barHeight)
                                .zIndex(0)

                            AnimatedBarGraph(index: monthsOfYear.firstIndex(of: month) ?? 0)
                                .frame(height: getBarHeight(point: monthDictionary[month] ?? 0, maxi: getMax))
                                .opacity(selectedDate == nil ? 1 : (selectedDate == month ? 1 : 0.4))
                                .zIndex(0)
                                .overlay(alignment: .bottom) {
                                    if numberArray.contains(((monthsOfYear.firstIndex(of: month) ?? 0) + 1)) {
                                        Text(LocalizedStringKey(monthNames[((monthsOfYear.firstIndex(of: month) ?? 0) + 1)] ?? ""))
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundColor(Color.SubtitleText)
                                            .frame(width: 30)
                                            .offset(y: 20)
                                    }
                                }
                        }
                        .padding(.bottom, 22)
                        .opacity(month > Date.now ? 0.3 : 1)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(!(month > Date.now))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(getMonth(month: month))
                        .accessibilityValue(String(format: "%.0f", monthDictionary[month] ?? 0))
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.2)) {
                                if selectedDate == month {
                                    selectedDate = nil
                                    categoryFilterMode = false
                                } else {
                                    selectedDate = month
                                    categoryFilterMode = false
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

            }
            .frame(maxWidth: .infinity)

            // average line

            AverageLineView(getMax: getMax, average: yearAverage)
                .opacity(actualMonths <= 1 ? 0 : 1)

        }
        .onChange(of: selectedDate) { _ in
            selectedDateAmount = monthDictionary[selectedDate ?? Date.now] ?? 0.0
        }
    }

    func getMonth(month: Date) -> String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "M"

        return dateFormatter.string(from: month)
    }

    init(year: Date, date: Binding<Date?>?, mode: Binding<Bool>, amount: Binding<Double>, dataController: DataController, income: Bool) {
        _selectedDate = date ?? Binding.constant(nil)
        _categoryFilterMode = mode
        _selectedDateAmount = amount

        let loaded = dataController.getInsights(type: 3, date: year, income: income)

        monthsOfYear = loaded.dates
        monthDictionary = loaded.dateDictionary
        self.max = loaded.maximum
        yearTotal = loaded.amount
        yearAverage = loaded.average
        actualMonths = loaded.numberOfDays
    }
}

func getMaxText(maxi: Int) -> String {
    if maxi == 0 {
        return "10"
    }

    let string = String(maxi)

    let stringArray = string.compactMap { String($0) }

    if maxi >= 1_000_000 {
        return stringArray[0] + "M"
    } else if maxi >= 100_000 {
        return string.prefix(3) + "k"
    } else if maxi >= 10000 {
        return string.prefix(2) + "k"
    } else if maxi >= 1000 {
        let string = String(maxi)

        let stringArray = string.compactMap { String($0) }

        return stringArray[0] + "." + stringArray[1] + "k"
    } else {
        return String(maxi)
    }
}

struct AnimatedBarGraph: View {
    var index: Int

    @AppStorage("animated", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var animated: Bool = true
    @State var showBar: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.blue)
                .frame(height: showBar ? nil : 0, alignment: .bottom)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                if !animated {
                    showBar = true
                } else {
                    withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.8).delay(Double(index) * 0.1)) {
                        showBar = true
                    }
                }
            }
        }
    }
}

struct AnimatedHorizontalBarGraph: View {
    @AppStorage("animated", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var animated: Bool = true
    var category: PowerCategory
    var index: Int

    @State var showBar: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(category.category.statisticsColor)
                .frame(width: showBar ? nil : 0, alignment: .leading)

            Spacer(minLength: 0)
        }
//        .onAppear {
//            DispatchQueue.main.asyncAfter(deadline: .now()) {
//                if !animated {
//                    showBar = true
//                } else {
//                    withAnimation(.easeInOut(duration: 0.7).delay(Double(index) * 0.5)) {
//                        showBar = true
//                    }
//                }
//            }
//        }
    }
}

struct InsightsDollarView: View {
    let amount: Double
    var currencySymbol: String
    var currencyCode: String?
    var showCents: Bool
    var net: Bool?
    var prominent: Bool

    private var formattedNumber: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        formatter.minimumFractionDigits = showCents && amount < 100 ? 2 : 0
        formatter.maximumFractionDigits = showCents && amount < 100 ? 2 : 0
        return formatter.string(from: NSNumber(value: abs(amount))) ?? "0"
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1.3) {
            Text(net == false ? "−\(currencySymbol)" : currencySymbol)
                .font(.system(prominent ? .title2 : .title3, design: .rounded).weight(.medium))
                .foregroundColor(net == false ? Color.AlertRed : Color.SubtitleText)

            Text(formattedNumber)
                .font(.system(prominent ? .largeTitle : .title, design: .rounded).weight(.medium))
                .foregroundColor(net == false ? Color.AlertRed : Color.PrimaryText)
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }

    init(amount: Double, currencySymbol: String, currencyCode: String? = nil, showCents: Bool, net: Bool? = nil, prominent: Bool = false) {
        self.amount = amount
        self.currencySymbol = currencySymbol
        self.currencyCode = currencyCode
        self.showCents = showCents
        self.net = net
        self.prominent = prominent
    }
}

func getAverageText(average: Double) -> String {
    let string = String(average)

    let stringArray = string.compactMap { String($0) }

    if average >= 1_000_000 {
        return stringArray[0] + "M"
    } else if average >= 100_000 {
        return string.prefix(3) + "k"
    } else if average >= 10000 {
        return string.prefix(2) + "k"
    } else if average >= 1000 {
        return stringArray[0] + "." + stringArray[1] + "k"
    } else {
        return String(Int(round(average)))
    }
}

let barHeight = 150.0

func getOffset(maxi: Int, average: Double) -> Double {
    if maxi == 0 {
        return 0
    } else {
        let shiftedAmount = (average / Double(maxi)) * (barHeight)
        let height = (barHeight) - (shiftedAmount)
        return height - 10
    }
}

func getBarHeight(point: CGFloat, maxi: Int) -> CGFloat {
    if maxi == 0 {
        return 0
    } else {
        let height = (point / CGFloat(maxi)) * barHeight
        return height
    }
}

struct SwipeArrowView: View {
    let left: Bool
    let swipeString: String
    let changeTime: Bool
    let isEnabled: Bool
    var action: () -> Void = {}

    init(left: Bool, swipeString: String, changeTime: Bool, isEnabled: Bool = true, action: @escaping () -> Void = {}) {
        self.left = left
        self.swipeString = swipeString
        self.changeTime = changeTime
        self.isEnabled = isEnabled
        self.action = action
    }

    private var buttonContent: some View {
        Button(action: action) {
            Image(systemName: left ? "chevron.left" : "chevron.right")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.PrimaryText)
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(left ? "Periodo precedente" : "Periodo successivo")
        .accessibilityValue(isEnabled ? "Disponibile" : "Non disponibile")
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                buttonContent
                    .glassEffect(.regular.interactive(), in: Circle())
            } else if #available(iOS 17.0, *) {
                buttonContent
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
            } else {
                buttonContent
                    .buttonStyle(.bordered)
            }
        }
        .zIndex(10)
    }
}

struct SwipeEndView: View {
    let left: Bool

    var body: some View {
        SwipeArrowView(left: left, swipeString: "", changeTime: false, isEnabled: false)
            .accessibilityHidden(true)
    }
}
