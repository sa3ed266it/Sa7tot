//
//  Sa7totApp.swift
//  Sa7tot
//
//  Created by Rafael Soh on 11/7/22.
//

import SwiftUI

@main
struct Sa7totApp: App {
    @StateObject var appLockVM = AppLockViewModel()
    @StateObject var authService: SupabaseAuthService
    @StateObject var remoteFinancialStore: FinancialRemoteStore
    @StateObject var appToastCoordinator = AppToastCoordinator()
    @StateObject var pushTokenCoordinator: PushTokenCoordinator

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AuthRootView()
                .environmentObject(appLockVM)
                .environmentObject(authService)
                .environmentObject(remoteFinancialStore)
                .environmentObject(appToastCoordinator)
                .environmentObject(pushTokenCoordinator)
        }
    }

    init() {
        let authService = SupabaseAuthService.current()
        let apiClient: APIClient?
        if let configuration = try? APIConfiguration.current() {
            apiClient = APIClient(configuration: configuration, tokenProvider: authService.tokenProvider)
        } else {
            apiClient = nil
        }

        _authService = StateObject(wrappedValue: authService)
        _remoteFinancialStore = StateObject(wrappedValue: FinancialRemoteStore(client: apiClient))
        _pushTokenCoordinator = StateObject(
            wrappedValue: PushTokenCoordinator(
                client: apiClient,
                tokenProvider: authService.tokenProvider
            )
        )

        UITableView.appearance().backgroundColor = .clear
    }
}
