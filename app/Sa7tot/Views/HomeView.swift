//
//  HomeView.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import ConfettiSwiftUI
import Foundation
import SwiftUI
import UIKit

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
    @EnvironmentObject var unlockManager: UnlockManager

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
        .sheet(item: $transactionManager.toEdit, onDismiss: {
            transactionManager.toEdit = nil
        }) { transaction in
            TransactionView(toEdit: transaction)
                .modifier(TransactionEditorSheetPresentation())
        }
        .sheet(isPresented: $addTransaction, onDismiss: {
            if confetti && addTransactionCount != transactions.count {
                counter += 1
            }
            if firstTransactionViewLaunch {
                firstTransactionViewLaunch = false
            }
        }) {
            TransactionView(toEdit: nil)
                .modifier(TransactionEditorSheetPresentation())
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
        NativeSearchTabView(
            selection: $currentTab,
            searchText: $searchText,
            logView: hosted(logTabContent),
            insightsView: hosted(InsightsView()),
            budgetView: hosted(BudgetView()),
            settingsView: hosted(SettingsView()),
            searchView: hosted(SearchView(searchQuery: $searchText))
        )
        .allowsHitTesting(showPopup ? false : true)
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

    private func hosted<V: View>(_ view: V) -> AnyView {
        AnyView(
            view
                .environment(\.managedObjectContext, moc)
                .environmentObject(appLockVM)
                .environmentObject(unlockManager)
                .environmentObject(dataController)
                .environmentObject(toastPresenter)
                .environmentObject(transactionManager)
        )
    }
}

private struct TransactionEditorSheetPresentation: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationDetents([.height(600), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(.thinMaterial)
        } else if #available(iOS 16.0, *) {
            content
                .presentationDetents([.height(600), .large])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

@available(iOS 26.0, *)
private final class InitialSelectionTabBarController: UITabBarController {
    private var didApplyInitialSelection = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didApplyInitialSelection,
              let tab = tab(forIdentifier: "Log") else { return }
        didApplyInitialSelection = true
        selectedTab = tab
    }
}

@available(iOS 26.0, *)
private struct NativeSearchTabView: UIViewControllerRepresentable {
    @Binding var selection: String
    @Binding var searchText: String
    let logView: AnyView
    let insightsView: AnyView
    let budgetView: AnyView
    let settingsView: AnyView
    let searchView: AnyView

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection, searchText: $searchText) }

    func makeUIViewController(context: Context) -> InitialSelectionTabBarController {
        let coordinator = context.coordinator
        let tabs: [UITab] = [
            UITab(title: "Movimenti", image: UIImage(systemName: "list.bullet.rectangle"), identifier: "Log") { _ in coordinator.host(logView) },
            UITab(title: "Statistiche", image: UIImage(systemName: "chart.bar.xaxis"), identifier: "Insights") { _ in coordinator.host(insightsView) },
            UITab(title: "Budget", image: UIImage(systemName: "chart.pie.fill"), identifier: "Budget") { _ in coordinator.host(budgetView) },
            UITab(title: "Impostazioni", image: UIImage(systemName: "gearshape"), identifier: "Settings") { _ in coordinator.host(settingsView) }
        ]
        let searchTab = UISearchTab { _ in coordinator.searchHost(searchView) }
        searchTab.automaticallyActivatesSearch = true
        let controller = InitialSelectionTabBarController(tabs: tabs + [searchTab])
        controller.delegate = coordinator
        controller.selectedTab = controller.tab(forIdentifier: "Log")
        return controller
    }

    func updateUIViewController(_ controller: InitialSelectionTabBarController, context: Context) {
        context.coordinator.searchText = $searchText
        guard controller.selectedTab?.identifier != selection,
              let tab = controller.tab(forIdentifier: selection) else { return }
        controller.selectedTab = tab
    }

    @MainActor
    final class Coordinator: NSObject, UITabBarControllerDelegate, UISearchResultsUpdating, UISearchBarDelegate {
        var selection: Binding<String>
        var searchText: Binding<String>
        private var searchController: UISearchController?

        init(selection: Binding<String>, searchText: Binding<String>) {
            self.selection = selection
            self.searchText = searchText
        }

        func host(_ view: AnyView) -> UIViewController { UIHostingController(rootView: view) }

        func searchHost(_ view: AnyView) -> UIViewController {
            let host = UIHostingController(rootView: view)
            let controller = UISearchController()
            controller.searchResultsUpdater = self
            controller.searchBar.delegate = self
            controller.searchBar.placeholder = "Cerca movimento per nota"
            controller.obscuresBackgroundDuringPresentation = false
            host.navigationItem.searchController = controller
            host.navigationItem.hidesSearchBarWhenScrolling = false
            host.definesPresentationContext = true
            searchController = controller
            return UINavigationController(rootViewController: host)
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            if let identifier = viewController.tab?.identifier { selection.wrappedValue = identifier }
        }

        func updateSearchResults(for searchController: UISearchController) {
            let text = searchController.searchBar.text ?? ""
            if self.searchText.wrappedValue != text { self.searchText.wrappedValue = text }
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            if self.searchText.wrappedValue != searchText { self.searchText.wrappedValue = searchText }
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
