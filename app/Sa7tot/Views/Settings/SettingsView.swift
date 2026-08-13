//
//  SettingsView.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
  let usesNativeNavigation: Bool
  let nativeNavigationRouter: NativeSettingsNavigationRouter?

  init(
    usesNativeNavigation: Bool = false,
    nativeNavigationRouter: NativeSettingsNavigationRouter? = nil
  ) {
    self.usesNativeNavigation = usesNativeNavigation
    self.nativeNavigationRouter = nativeNavigationRouter
  }

  @AppStorage("colourScheme", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var colourScheme: Int = 0

  @AppStorage("showNotifications", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var showNotifications: Bool = false
  @AppStorage("notificationsEnabled", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var notificationsEnabled: Bool = true
  @Environment(\.scenePhase) private var scenePhase
  @State private var notificationPermission: UNAuthorizationStatus = .notDetermined
  @State private var showingNotificationPermissionAlert = false
  @State private var financialCalendarErrorMessage: String?
  @State private var signOutErrorMessage: String?

  @EnvironmentObject var appLockVM: AppLockViewModel
  @EnvironmentObject private var authService: SupabaseAuthService
  @EnvironmentObject private var remoteStore: FinancialRemoteStore
  @EnvironmentObject private var pushTokenCoordinator: PushTokenCoordinator

  @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var showCents: Bool = true

  @AppStorage("haptics", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var hapticType: Int = 1

  // popups

  @State private var showingSignOutConfirmation = false

  var body: some View {
    Group {
      if #available(iOS 16.0, *) {
        if usesNativeNavigation { settingsList }
        else { NavigationStack { settingsList } }
      } else {
        if usesNativeNavigation { settingsList }
        else { NavigationView { settingsList } }
      }
    }
  }

  private var settingsList: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 24) {
        SettingsCard(title: "settings.preferences") {
          SettingsRowLayout(title: "settings.notifications", systemImage: "bell.fill", tint: .yellow) {
            Toggle("", isOn: notificationBinding)
              .labelsHidden()
              .tint(.green)
          }
        }

        SettingsCard(title: "settings.financialCalendar") {
          SettingsRowLayout(title: "settings.monthStartDay", systemImage: "calendar", tint: .purple) {
            Menu {
              Picker(AppLocalization.key("settings.monthStartDay"), selection: monthStartDayBinding) {
                ForEach(1...31, id: \.self) { day in
                  Text(String(day)).tag(day)
                }
              }
            } label: {
              SettingsMenuValue(text: String(financialMonthStartDay))
            }
            .accessibilityLabel(AppLocalization.key("settings.monthStartDay"))
            .accessibilityValue(String(financialMonthStartDay))
            .disabled(remoteStore.isUpdatingFinancialCalendar)
          }
          SettingsDivider()
          SettingsRowLayout(title: "settings.weekStartDay", systemImage: "calendar", tint: .indigo) {
            Menu {
              Picker(AppLocalization.key("settings.weekStartDay"), selection: weekStartDayBinding) {
                ForEach(FinancialWeekday.allCases) { weekday in
                  Text(AppLocalization.key(weekday.localizationKey)).tag(weekday.rawValue)
                }
              }
            } label: {
              SettingsMenuValue(text: AppLocalization.string(financialWeekday.localizationKey))
            }
            .accessibilityLabel(AppLocalization.key("settings.weekStartDay"))
            .accessibilityValue(AppLocalization.key(financialWeekday.localizationKey))
            .disabled(remoteStore.isUpdatingFinancialCalendar)
          }
        }

        SettingsCard(title: "settings.management") {
          if usesNativeNavigation {
            NativeSettingsNavigationRow(title: "account.title", subtitle: "settings.manageAccounts", systemImage: "building.columns.fill", tint: .blue) {
              if #available(iOS 26.0, *) {
                nativeNavigationRouter?.pushAccounts(RemoteAccountListView().environmentObject(remoteStore))
              } else {
                nativeNavigationRouter?.pushView(RemoteConfigurationUnavailableView())
              }
            }
          } else {
            SettingsNavigationRow(title: "account.title", subtitle: "settings.manageAccounts", systemImage: "building.columns.fill", tint: .blue) {
              if #available(iOS 26.0, *) {
                RemoteAccountListView()
              } else {
                RemoteConfigurationUnavailableView()
              }
            }
          }
          SettingsDivider()
          if usesNativeNavigation {
            NativeSettingsNavigationRow(title: "budget.title", subtitle: "settings.manageBudgets", systemImage: "chart.pie.fill", tint: .purple) {
              nativeNavigationRouter?.pushView(RemoteBudgetView().environmentObject(remoteStore))
            }
          } else {
            SettingsNavigationRow(title: "budget.title", subtitle: "settings.manageBudgets", systemImage: "chart.pie.fill", tint: .purple) {
              RemoteBudgetView()
            }
          }
        }

        SettingsCard(title: "settings.security") {
          SettingsRowLayout(title: "settings.authentication", systemImage: "faceid", tint: .blue) {
            Toggle("", isOn: appLockBinding)
              .labelsHidden()
              .tint(.green)
          }
        }

        SettingsCard(title: "settings.appearance") {
          SettingsRowLayout(title: "settings.theme", systemImage: "paintbrush.fill", tint: .blue) {
            Menu {
              Picker(AppLocalization.key("settings.theme"), selection: $colourScheme) {
                Text(AppLocalization.key("settings.system")).tag(0)
                Text(AppLocalization.key("settings.light")).tag(1)
                Text(AppLocalization.key("settings.dark")).tag(2)
              }
            } label: {
              SettingsMenuValue(text: themeValue)
            }
            .accessibilityLabel(AppLocalization.key("settings.theme"))
            .accessibilityValue(themeValue)
            .tint(.secondary)
          }
          SettingsDivider()
          SettingsRowLayout(title: "settings.showCents", systemImage: "centsign.circle.fill", tint: .teal) {
            Toggle("", isOn: $showCents).labelsHidden().tint(.green)
          }
        }

        SettingsCard(title: "settings.data") {
          if usesNativeNavigation {
            NativeSettingsNavigationRow(title: "category.title", subtitle: nil, systemImage: "rectangle.grid.2x2.fill", tint: .blue) {
              if #available(iOS 26.0, *) {
                nativeNavigationRouter?.pushView(RemoteCategoryListView().environmentObject(remoteStore))
              } else {
                nativeNavigationRouter?.pushView(RemoteConfigurationUnavailableView())
              }
            }
          } else {
            SettingsNavigationRow(title: "category.title", subtitle: nil, systemImage: "rectangle.grid.2x2.fill", tint: .blue) {
              if #available(iOS 26.0, *) {
                RemoteCategoryListView()
              } else {
                RemoteConfigurationUnavailableView()
              }
            }
          }
        }

        HStack {
          Spacer()
          Button(role: .destructive) {
            showingSignOutConfirmation = true
          } label: {
            SettingsRowLayout(
              title: "settings.signout",
              systemImage: "rectangle.portrait.and.arrow.right",
              tint: .red,
              titleColor: .red
            ) {
              EmptyView()
            }
            .fixedSize(horizontal: true, vertical: false)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(AppLocalization.key("settings.signout"))
          Spacer()
        }

      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .padding(.bottom, 120)
    }
    .navigationTitle(AppLocalization.key("settings.title"))
    .navigationBarTitleDisplayMode(.large)
    .dynamicTypeSize(...DynamicTypeSize.accessibility5)
    .onChange(of: scenePhase) { newPhase in
      if newPhase == .active { refreshNotificationPermission() }
    }
    .onAppear {
      refreshNotificationPermission()
    }
    .alert(AppLocalization.key("settings.notificationsDisabled"), isPresented: $showingNotificationPermissionAlert) {
      Button(AppLocalization.key("action.cancel"), role: .cancel) {}
      Button(AppLocalization.key("action.openSettings")) { openNotificationSettings() }
    } message: {
      Text(AppLocalization.key("settings.notificationsDisabledMessage"))
    }
    .alert(
      AppLocalization.key("settings.signout.confirm.title"),
      isPresented: $showingSignOutConfirmation
    ) {
      Button(AppLocalization.key("settings.signout.confirm.action"), role: .destructive) {
        Task {
          let didSignOut = await PushSignOutLifecycle.run(
            deactivate: {
              try await pushTokenCoordinator.deactivateCurrentRegistration()
            },
            signOut: {
              await authService.signOut()
            }
          )
          if !didSignOut {
            signOutErrorMessage = AppLocalization.string("error.generic")
          }
        }
      }
      Button(AppLocalization.key("action.cancel"), role: .cancel) {}
    } message: {
      Text(AppLocalization.key("settings.signout.confirm.message"))
    }
    .alert(
      AppLocalization.key("error.generic"),
      isPresented: Binding(
        get: { signOutErrorMessage != nil },
        set: { if !$0 { signOutErrorMessage = nil } }
      )
    ) {
      Button(AppLocalization.key("action.ok"), role: .cancel) {
        signOutErrorMessage = nil
      }
    } message: {
      Text(signOutErrorMessage ?? AppLocalization.string("error.generic"))
    }
    .alert(
      AppLocalization.key("error.generic"),
      isPresented: Binding(
        get: { financialCalendarErrorMessage != nil },
        set: { if !$0 { financialCalendarErrorMessage = nil } }
      )
    ) {
      Button(AppLocalization.key("action.ok"), role: .cancel) {
        financialCalendarErrorMessage = nil
      }
    } message: {
      Text(financialCalendarErrorMessage ?? AppLocalization.string("error.generic"))
    }
  }

  private var notificationBinding: Binding<Bool> {
    Binding(
      get: { showNotifications && notificationPermission != .denied },
      set: { setNotificationsEnabled($0) }
    )
  }

  private func setNotificationsEnabled(_ enabled: Bool) {
    if !enabled {
      showNotifications = false
      notificationsEnabled = false
      UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
      return
    }

    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      DispatchQueue.main.async {
        notificationPermission = settings.authorizationStatus
        switch settings.authorizationStatus {
        case .notDetermined:
          center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
              if granted {
                notificationPermission = .authorized
                showNotifications = true
                notificationsEnabled = true
                pushTokenCoordinator.registerIfAuthorized()
                newNotification()
              } else {
                notificationPermission = .denied
                showNotifications = false
                notificationsEnabled = false
              }
            }
          }
        case .authorized, .provisional, .ephemeral:
          showNotifications = true
          notificationsEnabled = true
          pushTokenCoordinator.registerIfAuthorized()
          newNotification()
        case .denied:
          showNotifications = false
          notificationsEnabled = false
          showingNotificationPermissionAlert = true
        @unknown default:
          showNotifications = false
          notificationsEnabled = false
        }
      }
    }
  }

  private func refreshNotificationPermission() {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        notificationPermission = settings.authorizationStatus
        if settings.authorizationStatus == .denied {
          let wasEnabled = showNotifications
          showNotifications = false
          notificationsEnabled = false
          if wasEnabled {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
          }
        }
      }
    }
  }

  private func openNotificationSettings() {
    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(settingsURL)
  }
  private var themeValue: String {
    switch colourScheme {
    case 1: return AppLocalization.string("settings.light")
    case 2: return AppLocalization.string("settings.dark")
    default: return AppLocalization.string("settings.system")
    }
  }

  private var appLockBinding: Binding<Bool> {
    Binding(
      get: { appLockVM.isAppLockEnabled },
      set: { appLockVM.appLockStateChange(appLockState: $0) }
    )
  }

  private var financialMonthStartDay: Int {
    remoteStore.profile?.monthStartDay ?? 1
  }

  private var financialWeekday: FinancialWeekday {
    FinancialWeekday(rawValue: remoteStore.profile?.weekStartDay ?? 1) ?? .monday
  }

  private var monthStartDayBinding: Binding<Int> {
    Binding(
      get: { financialMonthStartDay },
      set: { newValue in
        guard newValue != financialMonthStartDay else { return }
        updateFinancialCalendar(monthStartDay: newValue)
      }
    )
  }

  private var weekStartDayBinding: Binding<Int> {
    Binding(
      get: { financialWeekday.rawValue },
      set: { newValue in
        guard newValue != financialWeekday.rawValue else { return }
        updateFinancialCalendar(weekStartDay: newValue)
      }
    )
  }

  private func updateFinancialCalendar(monthStartDay: Int? = nil, weekStartDay: Int? = nil) {
    guard !remoteStore.isUpdatingFinancialCalendar else { return }
    Task { @MainActor in
      do {
        try await remoteStore.updateFinancialCalendar(
          monthStartDay: monthStartDay,
          weekStartDay: weekStartDay
        )
      } catch {
        financialCalendarErrorMessage = remoteStore.userFacingMessage(for: error)
      }
    }
  }

}

private enum FinancialWeekday: Int, CaseIterable, Identifiable {
  case monday = 1
  case tuesday
  case wednesday
  case thursday
  case friday
  case saturday
  case sunday

  var id: Int { rawValue }

  var localizationKey: String {
    switch self {
    case .monday: return "weekday.monday"
    case .tuesday: return "weekday.tuesday"
    case .wednesday: return "weekday.wednesday"
    case .thursday: return "weekday.thursday"
    case .friday: return "weekday.friday"
    case .saturday: return "weekday.saturday"
    case .sunday: return "weekday.sunday"
    }
  }
}

private struct SettingsCard<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(AppLocalization.key(title))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)

      VStack(spacing: 0) {
        content
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 2)
        .background(
        RoundedRectangle(cornerRadius: 23, style: .continuous)
          .fill(Color.AppSecondarySurface)
      )
    }
  }
}

private struct SettingsRowLayout<Trailing: View>: View {
  let title: String
  let subtitle: String?
  let systemImage: String
  let tint: Color
  let titleColor: Color
  @ViewBuilder let trailing: Trailing

  init(
    title: String,
    subtitle: String? = nil,
    systemImage: String,
    tint: Color,
    titleColor: Color = .primary,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.titleColor = titleColor
    self.trailing = trailing()
  }

  var body: some View {
    HStack(spacing: 14) {
      SettingsNativeIcon(systemImage: systemImage, tint: tint)

      VStack(alignment: .leading, spacing: 2) {
        Text(AppLocalization.key(title))
          .font(.body.weight(.medium))
          .foregroundStyle(titleColor)
          .fixedSize(horizontal: false, vertical: true)
        if let subtitle {
          Text(AppLocalization.key(subtitle))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .layoutPriority(1)

      Spacer(minLength: 10)
      trailing
    }
    .frame(minHeight: 58)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

private struct SettingsNavigationRow<Destination: View>: View {
  let title: String
  let subtitle: String?
  let systemImage: String
  let tint: Color
  @ViewBuilder let destination: Destination

  init(
    title: String,
    subtitle: String?,
    systemImage: String,
    tint: Color,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.destination = destination()
  }

  var body: some View {
    NavigationLink {
      destination
    } label: {
      SettingsRowLayout(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint
      ) {
        SettingsChevron()
      }
    }
    .buttonStyle(.plain)
  }
}

private struct NativeSettingsNavigationRow: View {
  let title: String
  let subtitle: String?
  let systemImage: String
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      SettingsRowLayout(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint
      ) {
        SettingsChevron()
      }
    }
    .buttonStyle(.plain)
  }
}

@MainActor
final class NativeSettingsNavigationRouter: ObservableObject {
  weak var navigationController: UINavigationController?

  func pushAccounts<Destination: View>(_ destination: Destination) {
    pushView(destination)
  }

  func pushView<Destination: View>(_ destination: Destination) {
    assert(
      navigationController?.tabBarController != nil,
      "Settings destinations must be pushed by the navigation controller inside the native tab bar controller."
    )
    guard let navigationController,
          navigationController.tabBarController != nil else { return }

    let controller = UIHostingController(rootView: destination)
    controller.hidesBottomBarWhenPushed = true
    navigationController.pushViewController(controller, animated: true)
  }
}

private struct SettingsMenuValue: View {
  let text: String

  var body: some View {
    HStack(spacing: 8) {
      Text(text)
        .font(.body)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Image(systemName: "chevron.down")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .fixedSize(horizontal: true, vertical: false)
    .foregroundStyle(.secondary)
  }
}

private struct SettingsChevron: View {
  var body: some View {
    Image(systemName: "chevron.right")
      .font(.body.weight(.semibold))
      .foregroundStyle(.tertiary)
      .accessibilityHidden(true)
  }
}

private struct SettingsDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.10))
      .frame(height: 0.5)
      .padding(.leading, 58)
  }
}

private struct SettingsNativeIcon: View {
  let systemImage: String
  let tint: Color

  var body: some View {
    Image(systemName: Sa7totSymbolResolver.resolved(systemImage))
      .font(.system(size: 17, weight: .semibold))
      .symbolRenderingMode(.hierarchical)
      .foregroundStyle(.primary)
      .frame(width: 38, height: 38)
      .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .accessibilityHidden(true)
  }
}
