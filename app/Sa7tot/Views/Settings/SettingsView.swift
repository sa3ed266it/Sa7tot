//
//  SettingsView.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import Combine
import ConfettiSwiftUI
import Foundation
import StoreKit
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

struct SettingsView: View {
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
  @Namespace var animation

  var iCloudString: String {
    if NSUbiquitousKeyValueStore.default.bool(forKey: "icloud_sync") {
      return String(localized: "On")
    } else {
      return String(localized: "Off")
    }
  }

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

  @AppStorage(
    "showUpcomingTransactions", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var showUpcoming: Bool = true

  var upcomingString: String {
    if showUpcoming {
      return String(localized: "Shown")
    } else {
      return String(localized: "Hidden")
    }
  }

    @AppStorage("haptics", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
    var hapticType: Int = 1

    var hapticString: String {
      if hapticType == 0 {
        return String(localized: "None")
      } else if hapticType == 1 {
        return String(localized: "Subtle")
      } else {
        return String(localized: "Excessive")
      }
    }

  // popups

  @State var showImportGuide = false
  @State private var showCategoriesSheet = false

  @EnvironmentObject var dataController: DataController

  var body: some View {
    Group {
      if #available(iOS 16.0, *) {
        NavigationStack { settingsList }
      } else {
        NavigationView { settingsList }
      }
    }
    .fullScreenCover(isPresented: $showImportGuide) { ImportDataView() }
    .sheet(isPresented: $showCategoriesSheet) {
      if #available(iOS 16.0, *) {
        NavigationStack {
          CategoryView(mode: .settings, income: false)
            .navigationTitle("Categorie")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      } else {
        NavigationView {
          CategoryView(mode: .settings, income: false)
            .navigationTitle("Categorie")
            .navigationBarTitleDisplayMode(.inline)
        }
      }
    }
  }

  private var settingsList: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 24) {
        SettingsCard(title: "PREFERENZE") {
          SettingsRowLayout(title: "Notifiche", systemImage: "bell.fill", tint: .yellow) {
            Toggle("", isOn: notificationBinding)
              .labelsHidden()
              .tint(.green)
          }
          SettingsDivider()
          SettingsRowLayout(title: "Valuta", systemImage: "eurosign", tint: .green) {
            Menu {
              Picker("Valuta", selection: $currency) {
                ForEach(Currency.allCurrencies, id: \.code) { item in
                  Text("\(item.code) — \(item.name)").tag(item.code)
                }
              }
            } label: {
              SettingsMenuValue(text: currency)
            }
            .accessibilityLabel("Valuta")
            .accessibilityValue(currency)
            .tint(.secondary)
          }
          SettingsDivider()
          SettingsRowLayout(title: "Inizio settimana", systemImage: "calendar", tint: .purple) {
            Menu {
              Picker("Inizio settimana", selection: $firstWeekday) {
                ForEach(Sa7totWeekday.allCases) { weekday in
                  Text(weekday.italianName).tag(weekday.rawValue)
                }
              }
            } label: {
              SettingsMenuValue(text: Sa7totWeekday(rawValue: firstWeekday)?.italianName ?? "Domenica")
            }
            .accessibilityLabel("Inizio settimana")
            .accessibilityValue(Sa7totWeekday(rawValue: firstWeekday)?.italianName ?? "Domenica")
            .tint(.secondary)
          }
        }

        SettingsCard(title: "GESTIONE") {
          SettingsNavigationRow(title: "Conti", subtitle: "Gestisci i tuoi conti", systemImage: "building.columns.fill", tint: .blue) {
            AccountListView()
          }
          SettingsDivider()
          SettingsNavigationRow(title: "Automazione Wallet", subtitle: "Comandi Rapidi", systemImage: "wallet.pass.fill", tint: .orange) {
            WalletAutomationView()
          }
        }

        SettingsCard(title: "MONITORAGGIO") {
          SettingsRowLayout(title: "Monitoraggio entrate", systemImage: "banknote.fill", tint: .green) {
            Toggle("", isOn: incomeTrackingBinding)
              .labelsHidden()
              .tint(.green)
          }
        }

        SettingsCard(title: "SICUREZZA") {
          SettingsRowLayout(title: "Autenticazione", systemImage: "faceid", tint: .blue) {
            Toggle("", isOn: appLockBinding)
              .labelsHidden()
              .tint(.green)
          }
        }

        SettingsCard(title: "ASPETTO") {
          SettingsRowLayout(title: "Tema", systemImage: "paintbrush.fill", tint: .blue) {
            Menu {
              Picker("Tema", selection: $colourScheme) {
                Text("Sistema").tag(0)
                Text("Chiaro").tag(1)
                Text("Scuro").tag(2)
              }
            } label: {
              SettingsMenuValue(text: themeValue)
            }
            .accessibilityLabel("Tema")
            .accessibilityValue(themeValue)
            .tint(.secondary)
          }
          SettingsDivider()
          SettingsRowLayout(title: "Mostra centesimi", systemImage: "centsign.circle.fill", tint: .teal) {
            Toggle("", isOn: $showCents).labelsHidden().tint(.green)
          }
          SettingsDivider()
          SettingsNavigationRow(title: "Movimenti futuri", subtitle: upcomingValue, systemImage: "clock.arrow.circlepath", tint: .orange) {
            SettingsUpcomingView()
          }
          SettingsDivider()
          SettingsRowLayout(title: "Mostra simbolo +/-", systemImage: "plus.forwardslash.minus", tint: .pink) {
            Toggle("", isOn: $showExpenseOrIncomeSign).labelsHidden().tint(.green)
          }
          SettingsDivider()
          SettingsRowLayout(title: "Grafici animati", systemImage: "hare.fill", tint: .mint) {
            Toggle("", isOn: $animated).labelsHidden().tint(.green)
          }
        }

        SettingsCard(title: "DATI") {
          Button { showCategoriesSheet = true } label: {
            SettingsRowLayout(title: "Categorie", systemImage: "rectangle.grid.2x2.fill", tint: .blue) {
              SettingsChevron()
            }
          }
          .buttonStyle(.plain)
          SettingsDivider()
          SettingsNavigationRow(title: "iCloud", subtitle: iCloudValue, systemImage: "icloud.fill", tint: .blue) {
            SettingsCloudView()
          }
          SettingsDivider()
          Button { showImportGuide = true } label: {
            SettingsRowLayout(title: "Importa dati", systemImage: "arrow.down.circle.fill", tint: .green) { EmptyView() }
          }
          .buttonStyle(.plain)
          SettingsDivider()
          Button { exportData() } label: {
            SettingsRowLayout(title: "Esporta dati", systemImage: "arrow.up.circle.fill", tint: .orange) { EmptyView() }
          }
          .buttonStyle(.plain)
          SettingsDivider()
          SettingsNavigationRow(title: "Elimina dati", subtitle: nil, systemImage: "trash.fill", tint: .red) {
            SettingsEraseView()
          }
        }

        SettingsCard(title: "AVANZATE") {
          SettingsNavigationRow(title: "Feedback aptico", subtitle: hapticValue, systemImage: "hand.tap.fill", tint: .pink) {
            SettingsHapticsView()
          }
          SettingsDivider()
          Button { } label: {
            SettingsRowLayout(title: "Laboratorio funzioni", systemImage: "flame.fill", tint: .orange) { EmptyView() }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .padding(.bottom, 120)
    }
    .navigationTitle("Impostazioni")
    .navigationBarTitleDisplayMode(.large)
    .dynamicTypeSize(...DynamicTypeSize.accessibility5)
    .onChange(of: firstWeekday) { newValue in
      if let weekday = Sa7totWeekday(rawValue: newValue) {
        Sa7totCalendarSettings.updateWeekday(weekday)
      }
    }
    .onChange(of: showCents) { _ in WidgetCenter.shared.reloadAllTimelines() }
    .onChange(of: currency) { newValue in
      NSUbiquitousKeyValueStore.default.set(newValue, forKey: "currency")
      WidgetCenter.shared.reloadAllTimelines()
    }
    .onChange(of: scenePhase) { newPhase in
      if newPhase == .active { refreshNotificationPermission() }
    }
    .onAppear {
      if !(1...7).contains(firstWeekday) { firstWeekday = 1 }
      refreshNotificationPermission()
    }
    .alert("Notifiche disattivate", isPresented: $showingNotificationPermissionAlert) {
      Button("Annulla", role: .cancel) {}
      Button("Apri Impostazioni") { openNotificationSettings() }
    } message: {
      Text("Le notifiche sono state disattivate nelle impostazioni di iOS. Abilita le notifiche per ricevere i promemoria.")
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
  private var upcomingValue: String {
    showUpcoming ? "Mostrati" : "Nascosti"
  }

  private var themeValue: String {
    switch colourScheme {
    case 1: return "Chiaro"
    case 2: return "Scuro"
    default: return "Sistema"
    }
  }

  private var iCloudValue: String {
    NSUbiquitousKeyValueStore.default.bool(forKey: "icloud_sync") ? "Attivo" : "Disattivo"
  }

  private var hapticValue: String {
    switch hapticType {
    case 0: return "Nessuno"
    case 1: return "Leggero"
    default: return "Intenso"
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
            false, forKey: "insightsViewIncomeFiltering")
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

  func exportData() {
    let fetchRequest = dataController.fetchRequestForExport()
    let transactions = dataController.results(for: fetchRequest)

    let fileName = "export.csv"
    let path = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
    var csvText = "Date,Note,Amount,Category,Type\n"

    for transaction in transactions {
      var string = transaction.wrappedNote
      let type: String

      if transaction.income {
        type = "Income"
      } else {
        type = "Expense"
      }

      string.removeAll(where: { $0 == "," })

      csvText +=
        "\(transaction.wrappedDate),\(string),\(String(format: "%.2f", transaction.wrappedAmount)),\(transaction.category?.wrappedName ?? ""),\(type)\n"
    }

    do {
      try csvText.write(to: path!, atomically: true, encoding: String.Encoding.utf8)
    } catch {
      print("\(error)")
    }

    var filesToShare = [Any]()
    filesToShare.append(path!)

    let av = UIActivityViewController(activityItems: filesToShare, applicationActivities: nil)

    let allScenes = UIApplication.shared.connectedScenes
    let scene = allScenes.first { $0.activationState == .foregroundActive }

    if let windowScene = scene as? UIWindowScene {
      windowScene.keyWindow?.rootViewController?.present(av, animated: true, completion: nil)
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
      Text(title)
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
          .fill(Color(uiColor: .secondarySystemBackground).opacity(0.94))
          .overlay(.regularMaterial.opacity(0.18), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
      )
    }
  }
}

private struct SettingsRowLayout<Trailing: View>: View {
  let title: String
  let subtitle: String?
  let systemImage: String
  let tint: Color
  @ViewBuilder let trailing: Trailing

  init(
    title: String,
    subtitle: String? = nil,
    systemImage: String,
    tint: Color,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.trailing = trailing()
  }

  var body: some View {
    HStack(spacing: 14) {
      SettingsNativeIcon(systemImage: systemImage, tint: tint)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body.weight(.medium))
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
        if let subtitle {
          Text(subtitle)
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
      Text(title)
        .font(.callout)
        .foregroundStyle(.primary)
    } icon: {
      SettingsNativeIcon(systemImage: systemImage, tint: tint)
    }
    .accessibilityLabel(title)
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
      Text(title)
        .font(.callout)
        .foregroundStyle(.primary)
        .lineLimit(2)
        .layoutPriority(1)
      Spacer(minLength: 8)
      if let value {
        Text(value)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
          .multilineTextAlignment(.trailing)
      }
    }
    .frame(minHeight: 44)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
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
      return "Tip failed to go through, please try again!"
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
    ZStack(alignment: .bottom) {
      Color.PrimaryBackground.opacity(opacity)
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
            Text("Loading")
              .font(.system(.body, design: .rounded).weight(.medium))
              //                            .font(.system(size: 18, weight: .medium, design: .rounded))
              .foregroundColor(Color.SubtitleText)
              .frame(maxWidth: .infinity)
              .frame(height: 200)
          }
        case .failed:
          Text("Unable to load tip options, please try again later 🥲")
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
              Text("Tip Jar")
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
                  .background(Color.SecondaryBackground, in: Circle())
                  .contentShape(Circle())
              }
              .offset(x: 5, y: -5)
            }

            Text(
              "Hey! Sa7tot was built by a solo student developer, and is intended to be completely free-of-charge, with no paywalls or ads. If you enjoy using Sa7tot and want to support development, please consider a small tip."
            )
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

            Text(bottomCaption)
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
        RoundedRectangle(cornerRadius: 13).fill(Color.PrimaryBackground).shadow(
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
                Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
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
