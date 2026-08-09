//
//  Sa7totApp.swift
//  Sa7tot
//
//  Created by Rafael Soh on 11/7/22.
//

import SwiftUI

@main
struct Sa7totApp: App {
    @StateObject var unlockManager: UnlockManager
    @StateObject var appLockVM = AppLockViewModel()
    @StateObject var authService: SupabaseAuthService
    @StateObject var remoteFinancialStore: FinancialRemoteStore

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AuthRootView()
                .environmentObject(appLockVM)
                .environmentObject(unlockManager)
                .environmentObject(authService)
                .environmentObject(remoteFinancialStore)
        }
    }

    init() {
        let unlockManager = UnlockManager()
        let authService = SupabaseAuthService.current()
        let apiClient: APIClient?
        if let configuration = try? APIConfiguration.current() {
            apiClient = APIClient(configuration: configuration, tokenProvider: authService.tokenProvider)
        } else {
            apiClient = nil
        }

        _unlockManager = StateObject(wrappedValue: unlockManager)
        _authService = StateObject(wrappedValue: authService)
        _remoteFinancialStore = StateObject(wrappedValue: FinancialRemoteStore(client: apiClient))

        UITableView.appearance().backgroundColor = .clear
    }
}
