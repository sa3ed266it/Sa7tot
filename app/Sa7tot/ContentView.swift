//
//  ContentView.swift
//
//  Created by Rafael Soh on 3/6/22.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appLockVM: AppLockViewModel

    @AppStorage("colourScheme", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var colourScheme: Int = 0
    @Environment(\.scenePhase) var scenePhase
    @AppStorage("showNotifications", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showNotifications: Bool = false
    @AppStorage("notificationsEnabled", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var notificationsEnabled: Bool = true

    @AppStorage("firstLaunch", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var firstLaunch: Bool = true

    @State var showUpdate: Bool = false

    var center = UNUserNotificationCenter.current()

    @AppStorage("topEdge", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var savedTopEdge: Double = 30
    @AppStorage("bottomEdge", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var savedBottomEdge: Double = 15

    // updateSheetShowing

    @AppStorage("previousVersion", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var previousVersionString: String = "Version \(UIApplication.appVersion ?? "") (\(UIApplication.buildNumber ?? ""))"

    @AppStorage("showUpdateSheet", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var showUpdateSheet: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let topEdge = proxy.safeAreaInsets.top
            let bottomEdge = proxy.safeAreaInsets.bottom

            HomeView(topEdge: topEdge, bottomEdge: bottomEdge == 0 ? 15 : bottomEdge)
                .ignoresSafeArea(.all, edges: .bottom)
                .preferredColorScheme(colourScheme == 1 ? .light : colourScheme == 2 ? .dark : nil)
                .fullScreenCover(isPresented: $showUpdate) {
                    UpdateAlert()
                }
                .onAppear {
                    savedTopEdge = topEdge
                    savedBottomEdge = bottomEdge
                }
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {

            if appLockVM.isAppLockEnabled {
                appLockVM.appLockValidation()
            }

            let defaults =
                UserDefaults(suiteName: "group.com.saied.sa7tot") ?? UserDefaults.standard
            defaults.removeObject(forKey: "firstDayOfMonth")


            if firstLaunch {
                firstLaunch = false
                showUpdateSheet = false

                defaults.set(0, forKey: "colourScheme")
                defaults.set(1, forKey: "firstWeekday")
                defaults.set(1, forKey: "haptics")
                defaults.set(1, forKey: "notificationOption")
                defaults.set(false, forKey: "confetti")
                defaults.set(false, forKey: "chromatic")
                defaults.set(true, forKey: "showCents")
                defaults.set(true, forKey: "animated")

                defaults.set(2, forKey: "numberEntryType")
            }

            if showUpdateSheet {
                showUpdate = true
                showUpdateSheet = false
            }

            center.getNotificationSettings { settings in
                if settings.authorizationStatus == .denied {
                    notificationsEnabled = false

                    if showNotifications {
                        showNotifications = false
                        center.removeAllPendingNotificationRequests()
                    }
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background || newPhase == .inactive {
                if appLockVM.isAppLockEnabled {
                    appLockVM.isAppUnLocked = false
                }
            } else if newPhase == .active {
                center.getNotificationSettings { settings in
                    if settings.authorizationStatus == .denied {
                        notificationsEnabled = false

                        if showNotifications {
                            showNotifications = false
                            center.removeAllPendingNotificationRequests()
                        }
                    }
                }
            }
        }
    }
}
