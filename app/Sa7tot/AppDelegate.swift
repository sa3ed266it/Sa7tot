//
//  AppDelegate.swift
//  sa7tot
//
//  Created by Rafael Soh on 24/8/22.
//

import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: "sa7totapp://search",
                localizedTitle: AppLocalization.string("shortcut.search"),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "magnifyingglass"),
                userInfo: nil
            ),
            UIApplicationShortcutItem(
                type: "sa7totapp://newExpense",
                localizedTitle: AppLocalization.string("shortcut.expense"),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "plus.app"),
                userInfo: nil
            )
        ]
        return true
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let sceneConfiguration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        sceneConfiguration.delegateClass = SceneDelegate.self
        return sceneConfiguration
    }
}
