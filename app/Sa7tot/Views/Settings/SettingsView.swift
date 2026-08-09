//
//  SettingsView.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import Combine
import Foundation
import StoreKit
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

  @Environment(\.dynamicTypeSize) var dynamicTypeSize

  @AppStorage("colourScheme", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var colourScheme: Int = 0
  @AppStorage("firstWeekday", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var firstWeekday: Int = 1

  @AppStorage("showNotifications", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var showNotifications: Bool = false
  @AppStorage("notificationsEnabled", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var notificationsEnabled: Bool = true
  @Environment(\.scenePhase) private var scenePhase
  @State private var notificationPermission: UNAuthorizationStatus = .notDetermined
  @State private var showingNotificationPermissionAlert = false

  @EnvironmentObject var appLockVM: AppLockViewModel
  @EnvironmentObject private var authService: SupabaseAuthService
  @EnvironmentObject private var remoteStore: FinancialRemoteStore
  @Namespace var animation

  @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var showCents: Bool = true

  @AppStorage("animated", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var animated:
    Bool = true

  @AppStorage("currency", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var currency:
    String = Locale.current.currencyCode!

  @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var incomeTracking: Bool = true
    
  @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var showExpenseOrIncomeSign: Bool = true

    @AppStorage("haptics", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
    var hapticType: Int = 1

    var hapticString: String {
      if hapticType == 0 {
        return AppLocalization.string("settings.haptics.none")
      } else if hapticType == 1 {
        return AppLocalization.string("settings.haptics.subtle")
      } else {
        return AppLocalization.string("settings.haptics.excessive")
      }
    }

  // popups

  @State private var showCategoriesSheet = false
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
    .sheet(isPresented: $showCategoriesSheet) {
      if #available(iOS 16.0, *) {
        NavigationStack {
          if #available(iOS 26.0, *) {
            RemoteCategoryListView()
          } else {
            RemoteConfigurationUnavailableView()
          }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      } else {
        NavigationView {
          RemoteConfigurationUnavailableView()
        }
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
          SettingsDivider()
          SettingsRowLayout(title: "common.currency", systemImage: "eurosign", tint: .green) {
            Menu {
              Picker(AppLocalization.key("common.currency"), selection: $currency) {
                ForEach(Currency.allCurrencies, id: \.code) { item in
                  Text("\(item.code) — \(item.name)").tag(item.code)
                }
              }
            } label: {
              SettingsMenuValue(text: currency)
            }
            .accessibilityLabel(AppLocalization.key("common.currency"))
            .accessibilityValue(currency)
            .tint(.secondary)
          }
          SettingsDivider()
          SettingsRowLayout(title: "settings.weekStart", systemImage: "calendar", tint: .purple) {
            Menu {
              Picker(AppLocalization.key("settings.weekStart"), selection: $firstWeekday) {
                ForEach(Sa7totWeekday.allCases) { weekday in
                  Text(verbatim: weekday.localizedName).tag(weekday.rawValue)
                }
              }
            } label: {
              SettingsMenuValue(text: Sa7totWeekday(rawValue: firstWeekday)?.localizedName ?? AppLocalization.string("weekday.sunday"))
            }
            .accessibilityLabel(AppLocalization.key("settings.weekStart"))
            .accessibilityValue(Sa7totWeekday(rawValue: firstWeekday)?.localizedName ?? AppLocalization.string("weekday.sunday"))
            .tint(.secondary)
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

        SettingsCard(title: "settings.monitoring") {
          SettingsRowLayout(title: "settings.incomeTracking", systemImage: "banknote.fill", tint: .green) {
            Toggle("", isOn: incomeTrackingBinding)
              .labelsHidden()
              .tint(.green)
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
          SettingsDivider()
          SettingsRowLayout(title: "settings.showSigns", systemImage: "plus.forwardslash.minus", tint: .pink) {
            Toggle("", isOn: $showExpenseOrIncomeSign).labelsHidden().tint(.green)
          }
          SettingsDivider()
          SettingsRowLayout(title: "settings.animatedCharts", systemImage: "hare.fill", tint: .mint) {
            Toggle("", isOn: $animated).labelsHidden().tint(.green)
          }
        }

        SettingsCard(title: "settings.data") {
          Button { showCategoriesSheet = true } label: {
            SettingsRowLayout(title: "category.title", systemImage: "rectangle.grid.2x2.fill", tint: .blue) {
              SettingsChevron()
            }
          }
          .buttonStyle(.plain)
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
    .onChange(of: firstWeekday) { newValue in
      if let weekday = Sa7totWeekday(rawValue: newValue) {
        Sa7totCalendarSettings.updateWeekday(weekday)
      }
    }
    .onChange(of: scenePhase) { newPhase in
      if newPhase == .active { refreshNotificationPermission() }
    }
    .onAppear {
      if !(1...7).contains(firstWeekday) { firstWeekday = 1 }
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
        Task { await authService.signOut() }
      }
      Button(AppLocalization.key("action.cancel"), role: .cancel) {}
    } message: {
      Text(AppLocalization.key("settings.signout.confirm.message"))
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

  private var hapticValue: String {
    switch hapticType {
    case 0: return AppLocalization.string("settings.haptics.none")
    case 1: return AppLocalization.string("settings.haptics.subtle")
    default: return AppLocalization.string("settings.haptics.excessive")
    }
  }

  private var appLockBinding: Binding<Bool> {
    Binding(
      get: { appLockVM.isAppLockEnabled },
      set: { appLockVM.appLockStateChange(appLockState: $0) }
    )
  }

  private var incomeTrackingBinding: Binding<Bool> {
    Binding(
      get: { incomeTracking },
      set: { newValue in
        incomeTracking = newValue
        if !newValue {
          UserDefaults(suiteName: "group.com.saied.sa7tot")?.set(
            3, forKey: "logInsightsType")
        }
      }
    )
  }

  @ViewBuilder
    func ToggleRow(icon: String, color: String, text: String, bool: Bool, smaller: Bool = false, onTap: @escaping () -> Void)
    -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
            .font(.system(smaller ? .subheadline : .body, design: .rounded))
        .foregroundColor(.white)
        .frame(
          width: dynamicTypeSize > .xLarge ? 40 : 30, height: dynamicTypeSize > .xLarge ? 40 : 30,
          alignment: .center
        )
        .background(Color(color), in: RoundedRectangle(cornerRadius: 6))

      Text(text)
        .font(.system(.body, design: .rounded).weight(.medium))
        .lineLimit(1)
        .foregroundColor(Color.PrimaryText)

      Spacer()

      ZStack(alignment: bool ? .trailing : .leading) {
        Capsule()
          .frame(width: 42, height: 28)
          .foregroundColor(bool ? .green : .gray.opacity(0.8))

        Circle()
          .foregroundColor(Color.white)
          .padding(2)
          .frame(width: 28, height: 28)
          .matchedGeometryEffect(id: "toggle\(color)", in: animation)
      }
      .onTapGesture {
        withAnimation {
          onTap()
        }
      }
    }
    .frame(maxWidth: .infinity)
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

private struct SettingsNativeLabel: View {
  let title: String
  let systemImage: String
  let tint: Color

  var body: some View {
    Label {
      Text(AppLocalization.key(title))
        .font(.callout)
        .foregroundStyle(.primary)
    } icon: {
      SettingsNativeIcon(systemImage: systemImage, tint: tint)
    }
    .accessibilityLabel(AppLocalization.key(title))
  }
}

private struct SettingsNativeRow: View {
  let title: String
  let systemImage: String
  let tint: Color
  let value: String?

  init(title: String, systemImage: String, tint: Color, value: String? = nil) {
    self.title = title
    self.systemImage = systemImage
    self.tint = tint
    self.value = value
  }

  var body: some View {
    HStack(spacing: 12) {
      SettingsNativeIcon(systemImage: systemImage, tint: tint)
      Text(AppLocalization.key(title))
        .font(.callout)
        .foregroundStyle(.primary)
        .lineLimit(2)
        .layoutPriority(1)
      Spacer(minLength: 8)
      if let value {
        Text(verbatim: value)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
          .multilineTextAlignment(.trailing)
      }
    }
    .frame(minHeight: 44)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(AppLocalization.key(title))
    .accessibilityValue(value ?? "")
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

#if false
struct TipJarAlert: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.colorScheme) var systemColorScheme
  @EnvironmentObject var unlockManager: UnlockManager

  @State private var offset: CGFloat = 0

  @AppStorage("bottomEdge", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var bottomEdge: Double = 15

  @State var opacity = 0.0
  @State var counter = 0

  var bottomCaption: String {
    if unlockManager.failedTransaction {
      return "La mancia non è andata a buon fine. Riprova!"
    } else if unlockManager.purchaseCount > 0 {
      return "Thanks a million, \(Image(systemName: "heart.fill")) Rafael"
    } else {
      return "Have a great day ahead!"
    }
  }

  //    var sortedProducts: [SKProduct] {
  //        let holding = unlockManager.loadedProducts.sorted {
  //            $0.price.doubleValue > $1.price.doubleValue
  //        }
  //
  //        return holding
  //    }

  var body: some View {
    let caption = bottomCaption
    let supportMessage = "Hey! Sa7tot was built by a solo student developer, and is intended to be completely free-of-charge, with no paywalls or ads. If you enjoy using Sa7tot and want to support development, please consider a small tip."

    ZStack(alignment: .bottom) {
      Color.AppPageBackground.opacity(opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
          withAnimation(.easeIn(duration: 0.15)) {
            opacity = 0
            offset += 300
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            dismiss()
          }
        }
        .onAppear {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation {
              opacity = 0.4
            }
          }
        }

      VStack {
        switch unlockManager.requestState {
        case .loading:
          ProgressView {
            Text("Caricamento")
              .font(.system(.body, design: .rounded).weight(.medium))
              //                            .font(.system(size: 18, weight: .medium, design: .rounded))
              .foregroundColor(Color.SubtitleText)
              .frame(maxWidth: .infinity)
              .frame(height: 200)
          }
        case .failed:
          Text("Impossibile caricare le opzioni per la mancia. Riprova più tardi 🥲")
            .font(.system(.body, design: .rounded).weight(.medium))

            //                        .font(.system(size: 18, weight: .medium, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundColor(Color.SubtitleText)
            .frame(maxWidth: .infinity)
            .frame(height: 200)
        default:
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Image(systemName: "heart.fill")
                .font(.system(.callout, design: .rounded))

              //                                .font(.system(size: 16))
              Text("Barattolo delle mance")
                .font(.system(.title2, design: .rounded).weight(.medium))

              //                                .font(.system(size: 22, weight: .medium, design: .rounded))
            }
            .foregroundColor(.PrimaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
              Button {
                withAnimation(.easeIn(duration: 0.15)) {
                  opacity = 0
                  offset += 300
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                  dismiss()
                }
              } label: {
                Image(systemName: "xmark")
                  .font(.system(.subheadline, design: .rounded).weight(.semibold))

                  //                                    .font(.system(size: 14, weight: .semibold))
                  .foregroundColor(Color.SubtitleText)
                  .padding(7)
                  .background(Color.AppSecondarySurface, in: Circle())
                  .contentShape(Circle())
              }
              .offset(x: 5, y: -5)
            }

            Text(supportMessage)
            .font(.system(.callout, design: .rounded).weight(.medium))

            //                            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundColor(.SubtitleText)
            .padding(.bottom, 20)

            ProductView(
              products: unlockManager.loadedProducts.sorted {
                $0.price.doubleValue < $1.price.doubleValue
              }
            )
            .padding(.bottom, 20)

            Text(verbatim: caption)
              .font(.system(.subheadline, design: .rounded).weight(.medium))

              //                                .font(.system(size: 14, weight: .medium, design: .rounded))
              .frame(maxWidth: .infinity)
              .foregroundColor(.SubtitleText)
          }
        }
      }
      .padding(18)
      .animation(.easeInOut, value: unlockManager.failedTransaction)
      .background(
        RoundedRectangle(cornerRadius: 13).fill(Color.AppPageBackground).shadow(
          color: systemColorScheme == .dark ? Color.clear : Color.gray.opacity(0.25), radius: 6)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 13).stroke(
          systemColorScheme == .dark ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3)
      )
      .offset(y: offset)
      .confettiCannon(
        counter: $counter, num: 50, openingAngle: Angle(degrees: 0),
        closingAngle: Angle(degrees: 360), radius: 200
      )
      .gesture(
        DragGesture()
          .onChanged { gesture in
            if gesture.translation.height < 0 {
              offset = gesture.translation.height / 3
            } else {
              offset = gesture.translation.height
            }
          }
          .onEnded { value in
            if value.translation.height > 30 {
              withAnimation(.easeIn(duration: 0.15)) {
                opacity = 0
                offset += 300
              }
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                dismiss()
              }

            } else {
              withAnimation {
                offset = 0
              }
            }
          }
      )
      .padding(.horizontal, 17)
      .padding(.bottom, bottomEdge == 0 ? 13 : bottomEdge)
      .onChange(of: unlockManager.purchaseCount) { _ in
        counter += 1
      }
    }
    .edgesIgnoringSafeArea(.all)
    .background(BackgroundBlurView())
  }
}

struct ProductView: View {
  @EnvironmentObject var unlockManager: UnlockManager
  let products: [SKProduct]

  var body: some View {
    VStack {
      ForEach(products, id: \.self) { product in
        HStack {
          Text(getText(product.productIdentifier))

          Spacer()

          Button {
            unlock(product)
          } label: {
            Text(product.localizedPrice)
              .monospacedDigit()
              .padding(6)
              .background(
                Color.AppSecondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
              )
          }
        }
      }
    }
    .foregroundColor(.PrimaryText)
    .font(.system(.body, design: .rounded).weight(.semibold))
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    //        .font(.system(size: 18, weight: .semibold, design: .rounded))
  }

  func unlock(_ product: SKProduct) {
    unlockManager.buy(product: product)
  }

  func getText(_ string: String) -> String {
    if string == "com.saied.sa7tot.smalltip" {
      return String(localized: "☕ Coffee-Sized Tip")
    } else if string == "com.saied.sa7tot.mediumtip" {
      return String(localized: "🌮 Taco-Sized Tip")
    } else if string == "com.saied.sa7tot.largetip" {
      return String(localized: "🍕 Pizza-Sized Tip")
    } else {
      return ""
    }
  }
}

#endif

struct SettingsRowView: View {
  var systemImage: String
  var title: String
  var colour: Int
  var optionalText: String?

  @Environment(\.dynamicTypeSize) var dynamicTypeSize

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(.body, design: .rounded))

        //                .font(.system(size: 17))
        //                .padding(5)
        .foregroundColor(.white)
        .frame(
          width: dynamicTypeSize > .xLarge ? 40 : 30, height: dynamicTypeSize > .xLarge ? 40 : 30,
          alignment: .center
        )
        .background(Color("\(colour)"), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

      Text(LocalizedStringKey(title))
        .font(.system(.body, design: .rounded).weight(.medium))

        //                .font(.system(size: 17, weight: .medium, design: .rounded))
        .lineLimit(1)
        .foregroundColor(Color.PrimaryText)

      Spacer()

      if optionalText != nil {
        Text(optionalText!)
          .font(.system(.body, design: .rounded))

          //                    .font(.system(size: 17, weight: .regular, design: .rounded))
          .foregroundColor(.DarkIcon.opacity(0.6))
          .layoutPriority(1)
          .padding(.trailing, -8)
      }

      Image(systemName: "chevron.forward")
        .font(.system(.subheadline, design: .rounded))
        //                .font(.system(size: 15))
        .foregroundColor(.DarkIcon.opacity(0.6))
    }
    .frame(maxWidth: .infinity)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }
}
