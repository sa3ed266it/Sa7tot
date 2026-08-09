import CrookedText
import Foundation
import SwiftUI

struct RemoteBudgetView: View {
    @EnvironmentObject private var remoteStore: FinancialRemoteStore

    var body: some View {
        if #available(iOS 26.0, *) {
            if remoteStore.isRemoteOnly {
                RemoteBudgetContent()
            } else {
                RemoteConfigurationUnavailableView()
            }
        } else {
            Text("Questa versione di iOS non è supportata.")
        }
    }
}

@available(iOS 26.0, *)
private struct RemoteBudgetContent: View {
    @EnvironmentObject private var store: FinancialRemoteStore
    @State private var showingNewBudget = false
    @State private var editingMain: RemoteMainBudgetDTO?
    @State private var editingCategory: RemoteCategoryBudgetDTO?
    @State private var deletingMain = false
    @State private var deletingCategory: RemoteCategoryBudgetDTO?
    private let categoryGridLayout = [
        GridItem(.flexible(), spacing: 15),
        GridItem(.flexible(), spacing: 15)
    ]

    var body: some View {
        ZStack {
            Color.AppPageBackground.ignoresSafeArea()
            Group {
                if let summary = store.budgetSummary, summary.main != nil || !summary.categories.isEmpty {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 15) {
                            if let main = summary.main {
                                RemoteMainBudgetCard(budget: main, onEdit: { editingMain = main }, onDelete: { deletingMain = true })
                                    .padding(.horizontal, 25)
                            }
                            if !summary.categories.isEmpty {
                                categorySection(summary.categories)
                            }
                        }
                        .padding(.bottom, 70)
                    }
                } else if store.isBudgetLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    BudgetEmptyState()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Budget")
        .navigationBarTitleDisplayMode(.inline)
        .budgetNavigationBackground()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingNewBudget = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nuovo budget")
            }
        }
        .task {
            await store.loadBudget()
        }
        .sheet(isPresented: $showingNewBudget) {
            RemoteBudgetEditor(overallBudgetCreated: store.budgetSummary?.main != nil)
                .environmentObject(store)
        }
        .sheet(item: $editingMain) { budget in
            RemoteBudgetEditor(mainBudget: budget).environmentObject(store)
        }
        .sheet(item: $editingCategory) { budget in
            RemoteBudgetEditor(categoryBudget: budget).environmentObject(store)
        }
        .alert("Eliminare il budget?", isPresented: $deletingMain) {
            Button("Elimina", role: .destructive) {
                Task { try? await store.deleteMainBudget() }
            }
            Button("Annulla", role: .cancel) {}
        }
        .alert("Eliminare il budget?", isPresented: Binding(
            get: { deletingCategory != nil },
            set: { if !$0 { deletingCategory = nil } }
        )) {
            Button("Elimina", role: .destructive) {
                guard let budget = deletingCategory else { return }
                Task { try? await store.deleteCategoryBudget(categoryID: budget.categoryID) }
            }
            Button("Annulla", role: .cancel) {}
        }
        .alert("Impossibile caricare il budget", isPresented: Binding(
            get: { store.budgetErrorMessage != nil },
            set: { _ in }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.budgetErrorMessage ?? "Riprova più tardi.")
        }
    }

    private func categoryCard(_ category: RemoteCategoryBudgetDTO) -> some View {
        RemoteCategoryBudgetCard(
            budget: category,
            onEdit: { editingCategory = category },
            onDelete: { deletingCategory = category }
        )
    }

    @ViewBuilder
    private func categorySection(_ categories: [RemoteCategoryBudgetDTO]) -> some View {
        if UserDefaults(suiteName: "group.com.saied.sa7tot")?.bool(forKey: "budgetViewStyle") == true {
            VStack(spacing: 10) {
                ForEach(categories) { category in categoryCard(category) }
            }
        } else {
            LazyVGrid(columns: categoryGridLayout, spacing: 15) {
                ForEach(categories) { category in categoryCard(category) }
            }
            .padding(.horizontal, 25)
            .padding(5)
        }
    }
}

@available(iOS 26.0, *)
private struct RemoteMainBudgetCard: View {
    let budget: RemoteMainBudgetDTO
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var total: Double { Double(budget.amountMinor) / pow(10, Double(budget.currencyExponent)) }
    private var spent: Double { Double(budget.spentMinor) / pow(10, Double(budget.currencyExponent)) }
    private var difference: Double { abs(total - spent) }
    private var periodName: String {
        switch budget.periodType { case .day: "oggi"; case .week: "questa settimana"; case .month: "questo mese"; case .year: "quest’anno" }
    }
    private var width: CGFloat { 250 }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                ZStack {
                    DonutSemicircle(percent: 1, cornerRadius: 6.5, width: 25)
                        .fill(Color.AppSecondarySurface)
                        .frame(width: width, height: width / 2)
                    DonutSemicircle(percent: max(0, 1 - budget.progress), cornerRadius: 6.5, width: 25)
                        .fill(Color.DarkBackground)
                        .frame(width: width, height: width / 2)
                }
                CrookedText(text: "SPESA COMPLESSIVA: \(Int(round(budget.progress * 100)))%", radius: width / 2 + 8)
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundColor(Color.SubtitleText)
                    .frame(width: width, height: 10)
                VStack(spacing: -4) {
                    BudgetDollarView(amount: difference, red: spent >= total, scale: 3, size: width - 60)
                        .frame(width: width - 60)
                    Text("\(total >= spent ? "restante" : "oltre") \(periodName)")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundColor(Color.SubtitleText)
                }
            }
            HStack {
                Text(remoteBudgetDisplay(budget.spentMinor, code: budget.currencyCode, exponent: budget.currencyExponent)).monospacedDigit().frame(width: 60, alignment: .leading)
                Spacer()
                Text(remoteBudgetDisplay(budget.amountMinor, code: budget.currencyCode, exponent: budget.currencyExponent)).monospacedDigit().frame(width: 60, alignment: .trailing)
            }
            .font(.system(.caption2, design: .rounded).weight(.medium))
            .frame(width: width)
            .foregroundColor(Color.SubtitleText)
        }
        .padding(.bottom)
        .frame(width: width + 30, height: 200, alignment: .bottom)
        .background(Color.AppPageBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .contextMenu {
            Button(action: onEdit) { Label("Modifica", systemImage: "pencil") }
            Button(role: .destructive, action: onDelete) { Label("Elimina", systemImage: "xmark.bin") }
        }
    }
}

@available(iOS 26.0, *)
private struct RemoteCategoryBudgetCard: View {
    let budget: RemoteCategoryBudgetDTO
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var total: Double { Double(budget.amountMinor) / pow(10, Double(budget.currencyExponent)) }
    private var spent: Double { Double(budget.spentMinor) / pow(10, Double(budget.currencyExponent)) }
    private var name: String { budget.categoryName ?? "Categoria rimossa" }
    private var color: Color { Color(hex: budget.categoryColor ?? "#FFFFFF") }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7.5) {
                Image(systemName: "tag.fill").foregroundStyle(color)
                Text(name).font(.system(.headline, design: .rounded).weight(.medium)).lineLimit(1)
            }
            .foregroundColor(Color.PrimaryText)
            Text(remoteBudgetDisplay(budget.remainingMinor, code: budget.currencyCode, exponent: budget.currencyExponent))
                .font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                .foregroundStyle(spent > total ? Color.BudgetRed : Color.PrimaryText)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 11.5, style: .continuous).fill(Color.AppSecondarySurface)
                    RoundedRectangle(cornerRadius: 11.5, style: .continuous).fill(color).frame(width: proxy.size.width * min(max(budget.progress, 0), 1))
                }
            }
            .frame(height: 28)
            HStack {
                Text(remoteBudgetDisplay(budget.spentMinor, code: budget.currencyCode, exponent: budget.currencyExponent))
                Spacer()
                Text(remoteBudgetDisplay(budget.amountMinor, code: budget.currencyCode, exponent: budget.currencyExponent))
            }
            .font(.system(.caption, design: .rounded)).foregroundColor(Color.SubtitleText).monospacedDigit()
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color.AppPageBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .contextMenu {
            Button(action: onEdit) { Label("Modifica", systemImage: "pencil") }
            Button(role: .destructive, action: onDelete) { Label("Elimina", systemImage: "xmark.bin") }
        }
    }
}

private func remoteBudgetDisplay(_ minor: Int64, code: String, exponent: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    formatter.minimumFractionDigits = exponent
    formatter.maximumFractionDigits = exponent
    let value = NSDecimalNumber(mantissa: UInt64(abs(minor)), exponent: Int16(-exponent), isNegative: minor < 0)
    return formatter.string(from: value) ?? "0"
}

private struct BudgetEmptyState: View {
    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                ContentUnavailableView {
                    Label("Nessun budget", systemImage: "chart.pie")
                } description: {
                    Text("Aggiungi il tuo primo budget.")
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Nessun budget")
                        .font(.title3.weight(.medium))
                    Text("Aggiungi il tuo primo budget.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding()
            }
        }
        .foregroundStyle(.primary)
    }
}

struct BudgetDollarView: View {
    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showCents: Bool = true

    var amount: Double
    var red: Bool
    var scale: Int
    var size: CGFloat

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String { Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)! }

    var dynamicTypeSizes: (symbol: Font.TextStyle, amount: Font.TextStyle) {
        if scale == 1 { return (.callout, .title3) }
        if scale == 2 { return (.body, .title2) }
        return (.title2, .largeTitle)
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1.3) {
            Text(currencySymbol)
                .font(.system(dynamicTypeSizes.symbol, design: .rounded).weight(.medium))
                .foregroundColor(red ? Color("BudgetRed") : Color.SubtitleText) +
            Text("\(amount, specifier: showCents && amount < 100 ? "%.2f" : "%.0f")")
                .font(.system(dynamicTypeSizes.amount, design: .rounded).weight(.medium))
                .foregroundColor(red ? Color("BudgetRed") : Color.PrimaryText)
                .monospacedDigit()
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
}

private extension View {
    @ViewBuilder
    func budgetNavigationBackground() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbarBackground(.hidden, for: .navigationBar)
        } else {
            self
        }
    }
}
