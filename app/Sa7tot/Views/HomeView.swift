//
//  HomeView.swift
//  Sa7tot
//

import Foundation
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var remoteFinancialStore: FinancialRemoteStore

    let topEdge: CGFloat
    let bottomEdge: CGFloat

    init(topEdge: CGFloat, bottomEdge: CGFloat) {
        self.topEdge = topEdge
        self.bottomEdge = bottomEdge
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            if remoteFinancialStore.isRemoteOnly {
                RemoteFinancialHomeView(topEdge: topEdge, bottomEdge: bottomEdge)
            } else {
                RemoteConfigurationUnavailableView()
            }
        } else {
            Text(AppLocalization.key("unsupported.ios"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@available(iOS 26.0, *)
final class InitialSelectionTabBarController: UITabBarController {
    private var didApplyInitialSelection = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didApplyInitialSelection,
              let tab = tab(forIdentifier: Sa7totMainTabConfiguration.movements) else { return }
        didApplyInitialSelection = true
        selectedTab = tab
    }
}

@available(iOS 26.0, *)
struct NativeSearchTabView: UIViewControllerRepresentable {
    @Binding var selection: String
    let logView: AnyView
    let subscriptionView: AnyView
    let settingsView: AnyView
    let settingsNavigationRouter: NativeSettingsNavigationRouter
    let onAdd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, settingsNavigationRouter: settingsNavigationRouter, onAdd: onAdd)
    }

    func makeUIViewController(context: Context) -> InitialSelectionTabBarController {
        let coordinator = context.coordinator
        let tabs: [UITab] = [
            UITab(
                title: AppLocalization.string("tab.movements"),
                image: Sa7totSymbolResolver.image("list.bullet.rectangle"),
                identifier: Sa7totMainTabConfiguration.movements
            ) { _ in coordinator.movementsHost(logView) },
            UITab(
                title: AppLocalization.string("tab.subscriptions"),
                image: Sa7totSymbolResolver.image("repeat"),
                identifier: Sa7totMainTabConfiguration.subscriptions
            ) { _ in coordinator.host(subscriptionView) },
            UITab(
                title: AppLocalization.string("tab.settings"),
                image: Sa7totSymbolResolver.image("gearshape.fill"),
                identifier: Sa7totMainTabConfiguration.settings
            ) { _ in coordinator.settingsHost(settingsView) }
        ]

        let addTab = UISearchTab { _ in
            let placeholder = UIViewController()
            placeholder.tabBarItem.accessibilityLabel = Sa7totMainTabConfiguration.trailingAddTitle
            return placeholder
        }
        addTab.image = Sa7totSymbolResolver.image("plus")
        addTab.title = Sa7totMainTabConfiguration.trailingAddTitle
        addTab.automaticallyActivatesSearch = false

        let controller = InitialSelectionTabBarController(tabs: tabs + [addTab])
        controller.delegate = coordinator
        controller.selectedTab = controller.tab(forIdentifier: Sa7totMainTabConfiguration.movements)
        return controller
    }

    func updateUIViewController(_ controller: InitialSelectionTabBarController, context: Context) {
        guard controller.selectedTab?.identifier != selection,
              let tab = controller.tab(forIdentifier: selection) else { return }
        controller.selectedTab = tab
    }

    @MainActor
    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var selection: Binding<String>
        let settingsNavigationRouter: NativeSettingsNavigationRouter
        let onAdd: () -> Void

        init(
            selection: Binding<String>,
            settingsNavigationRouter: NativeSettingsNavigationRouter,
            onAdd: @escaping () -> Void
        ) {
            self.selection = selection
            self.settingsNavigationRouter = settingsNavigationRouter
            self.onAdd = onAdd
        }

        func host(_ view: AnyView) -> UIViewController {
            UIHostingController(rootView: view)
        }

        func movementsHost(_ view: AnyView) -> UIViewController {
            let host = UIHostingController(rootView: view)
            return UINavigationController(rootViewController: host)
        }

        func settingsHost(_ view: AnyView) -> UIViewController {
            let settingsRoot = UIHostingController(rootView: view)
            let navigationController = UINavigationController(rootViewController: settingsRoot)
            settingsNavigationRouter.navigationController = navigationController
            return navigationController
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            guard tab is UISearchTab else { return true }
            onAdd()
            return false
        }

        @available(iOS 26.0, *)
        func tabBarController(_ tabBarController: UITabBarController, didSelectTab tab: UITab, previousTab: UITab?) {
            updateSelection(for: tab)
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            updateSelection(for: viewController.tab)
        }

        private func updateSelection(for tab: UITab?) {
            guard !(tab is UISearchTab),
                  let identifier = tab?.identifier else { return }
            selection.wrappedValue = identifier
        }
    }
}
