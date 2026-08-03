//
//  HomeView.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import ConfettiSwiftUI
import Foundation
import SwiftUI

class OverallToastPresenter: ObservableObject {
    @Published var showToast: Bool = false
}

enum DeletionType {
    case instant
    case prompt
}

class OverallTransactionManager: ObservableObject {
    @Published var toEdit: Transaction?
    @Published var toDelete: Transaction?
    @Published var showToast: Bool = false
    @Published var showPopup: Bool = false
    @Published var future: Bool = false
}

struct HomeView: View {
    @EnvironmentObject var appLockVM: AppLockViewModel

    @StateObject var toastPresenter = OverallToastPresenter()
    @StateObject var transactionManager = OverallTransactionManager()
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController

    @State var currentTab = "Log"
    @State private var searchText = ""
    @State private var suppressInitialSearchActivation = true
    @State private var launchedFromSearchURL = false

    var topEdge: CGFloat
    var bottomEdge: CGFloat

    @State var fromURL1: Bool = false
    @State var fromURL2: Bool = false
    @State var fromURL3: Bool = false
    @State var fromURL4: Bool = false

    @State var launchAdd: Bool = false
    @State var counter = 0

    @State var showPopup = false

    @FetchRequest(sortDescriptors: []) private var transactions: FetchedResults<Transaction>
    @State private var addTransaction = false
    @State private var addTransactionCount = 0

    @AppStorage("confetti", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) private var confetti = false
    @AppStorage("firstTransactionViewLaunch", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) private var firstTransactionViewLaunch = true

    init(topEdge: CGFloat, bottomEdge: CGFloat) {
        self.topEdge = topEdge
        self.bottomEdge = bottomEdge
    }

    var body: some View {
        ZStack {
            if #available(iOS 26.0, *) {
                modernTabView
            } else {
                legacyTabView
            }

            if showPopup {
                Rectangle()
                    .fill(Color.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        transactionManager.showPopup = false
                    }
            }

            DeleteTransactionAlert()
                .offset(y: showPopup ? 0 : 300)
                .environmentObject(transactionManager)

            if appLockVM.isAppLockEnabled && !appLockVM.isAppUnLocked {
                AppLockView()
                    .ignoresSafeArea(.all)
                    .onOpenURL { url in

                        if url.host == "newExpense" {
                            fromURL1 = true
                        } else if url.host == "search" {
                            launchedFromSearchURL = true
                            fromURL2 = true
                        } else if url.host == "insights" {
                            fromURL3 = true
                        } else if url.host == "budget" {
                            fromURL4 = true
                        }
                    }
            }
        }
        .toast(isPresenting: $toastPresenter.showToast, duration: 4, tapToDismiss: true, offsetY: 12, alert: {
            AlertToast(displayMode: .hud, type: .systemImage("checkmark.circle.fill", Color.IncomeGreen), title: "Image Saved", subTitle: "Check it out in Photos")
        })
        .toast(isPresenting: $transactionManager.showToast, duration: 4, tapToDismiss: true, offsetY: 12, alert: {
            AlertToast(displayMode: .hud, type: .systemImage("arrow.uturn.backward.circle.fill", Color.AlertRed), title: "Log Deleted", subTitle: "Tap to Undo")
        }, onTap: {
            withAnimation(.easeInOut(duration: 0.5)) {
                moc.rollback()
            }
            transactionManager.toDelete = nil
        }, completion: {
            dataController.save()
            transactionManager.toDelete = nil
        })
        .onChange(of: transactionManager.showPopup) { newValue in
            withAnimation {
                showPopup = newValue
            }
        }
        .fullScreenCover(item: $transactionManager.toEdit, onDismiss: {
            transactionManager.toEdit = nil
        }) { transaction in
            TransactionView(toEdit: transaction)
        }
        .fullScreenCover(isPresented: $addTransaction, onDismiss: {
            if confetti && addTransactionCount != transactions.count {
                counter += 1
            }
            if firstTransactionViewLaunch {
                firstTransactionViewLaunch = false
            }
        }) {
            TransactionView(toEdit: nil)
        }
        .confettiCannon(counter: $counter, num: 50, openingAngle: Angle(degrees: 0), closingAngle: Angle(degrees: 360), radius: 200)
        .onAppear {
            if appLockVM.isAppLockEnabled && fromURL1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    launchAdd.toggle()
                }

                fromURL1 = false
            }

            if appLockVM.isAppLockEnabled && fromURL2 {
                currentTab = "Search"
                fromURL2 = false
            }

            if appLockVM.isAppLockEnabled && fromURL3 {
                currentTab = "Insights"
            }

            if appLockVM.isAppLockEnabled && fromURL4 {
                currentTab = "Budget"
            }

            if suppressInitialSearchActivation {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !launchedFromSearchURL {
                        currentTab = "Log"
                    }
                    suppressInitialSearchActivation = false
                }
            }
        }
        .onOpenURL { url in
            if url.host == "newExpense" {
                if appLockVM.isAppLockEnabled && !appLockVM.isAppUnLocked {
                    fromURL1 = true
                } else {
                    presentAddMovement()
                }
            } else if url.host == "search" {
                if appLockVM.isAppLockEnabled && !appLockVM.isAppUnLocked {
                    launchedFromSearchURL = true
                    fromURL2 = true
                } else {
                    launchedFromSearchURL = true
                    currentTab = "Search"
                }
            } else if url.host == "insights" {
                currentTab = "Insights"
            } else if url.host == "budget" {
                currentTab = "Budget"
            }
        }
    }

    private func presentAddMovement() {
        guard !addTransaction else { return }
        addTransactionCount = transactions.count
        addTransaction = true
    }

    @available(iOS 26.0, *)
    private var modernTabView: some View {
        TabView(selection: $currentTab) {
            Tab("Movimenti", systemImage: "list.bullet.rectangle", value: "Log", role: nil) {
                logTabContent
            }
            Tab("Statistiche", systemImage: "chart.bar.xaxis", value: "Insights", role: nil) {
                InsightsView()
            }
            Tab("Budget", systemImage: "chart.pie.fill", value: "Budget", role: nil) {
                BudgetView()
            }
            Tab("Impostazioni", systemImage: "gearshape", value: "Settings", role: nil) {
                SettingsView()
            }
            Tab(value: "Search", role: .search) {
                searchTabContent
            }
        }
        .modifier(ConditionalSearchActivation(isActive: currentTab == "Search" && !suppressInitialSearchActivation))
        .allowsHitTesting(showPopup ? false : true)
        .environmentObject(toastPresenter)
        .environmentObject(transactionManager)
    }

    private var legacyTabView: some View {
        TabView(selection: $currentTab) {
            logTabContent
                .tabItem { Label("Movimenti", systemImage: "list.bullet.rectangle") }
                .tag("Log")
            InsightsView()
                .tabItem { Label("Statistiche", systemImage: "chart.bar.xaxis") }
                .tag("Insights")
            BudgetView()
                .tabItem { Label("Budget", systemImage: "chart.pie.fill") }
                .tag("Budget")
            SettingsView()
                .tabItem { Label("Impostazioni", systemImage: "gearshape") }
                .tag("Settings")
            SearchTabView(searchText: $searchText)
                .tabItem { Label("Cerca", systemImage: "magnifyingglass") }
                .tag("Search")
        }
        .allowsHitTesting(showPopup ? false : true)
        .environmentObject(toastPresenter)
        .environmentObject(transactionManager)
    }

    private var logTabContent: some View {
        LogView(
            topEdge: topEdge,
            bottomEdge: bottomEdge,
            launchAdd: launchAdd,
            onAdd: presentAddMovement
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @available(iOS 16.0, *)
    @ViewBuilder
    private var searchTabContent: some View {
        NavigationStack {
            if currentTab == "Search" && !suppressInitialSearchActivation {
                SearchView(searchQuery: $searchText)
                    .searchable(text: $searchText, prompt: "Cerca movimento per nota")
            } else {
                SearchView(searchQuery: $searchText)
            }
        }
    }
}

@available(iOS 26.0, *)
private struct ConditionalSearchActivation: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.tabViewSearchActivation(.searchTabSelection)
        } else {
            content
        }
    }
}

private struct SearchTabView: View {
    @Binding var searchText: String

    var body: some View {
        NavigationView {
            SearchView(searchQuery: $searchText)
                .sa7totLegacySearchable(text: $searchText)
                .navigationTitle("Cerca")
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

private extension View {
    @ViewBuilder
    func sa7totLegacySearchable(text: Binding<String>) -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            searchable(text: text, placement: .automatic, prompt: "Cerca movimento per nota")
        }
    }
}

struct AppLockView: View {
    @EnvironmentObject var appLockVM: AppLockViewModel

    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "lock.fill")
                .font(.system(size: 65))
                .foregroundColor(Color.DarkIcon.opacity(0.7))

            Text("App Locked")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(Color.PrimaryText)
                .padding(.bottom, 30)

            Button {
                appLockVM.appLockValidation()
            } label: {
                HStack {
                    Image(systemName: "faceid")

                    Text("Unlock App")
                }
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(Color.PrimaryText)
                .padding(.horizontal, 40)
                .padding(.vertical, 15)
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.Outline)
                }
            }

            if appLockVM.enrollmentError {
                Text("Please re-enable Face ID access in the Settings app to unlock application.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.PrimaryBackground)
    }
}
