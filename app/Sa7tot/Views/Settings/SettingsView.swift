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
  @AppStorage("notificationOption", store: UserDefaults(suiteName: "group.com.saied.sa7tot"))
  var option: Int = 1
  var notificationString: String {
    if showNotifications {
      if option == 1 {
        return String(localized: "Mornings")
      } else if option == 2 {
        return String(localized: "Evenings")
      } else {
        return String(localized: "Custom")
      }
    } else {
      return String(localized: "Off")
    }
  }

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
  }

  private var settingsList: some View {
    List {
      Section("Generale") {
        NavigationLink(destination: SettingsNotificationsView()) {
          SettingsNativeRow(title: "Notifiche", systemImage: "bell.fill", tint: .yellow, value: notificationValue)
        }
        NavigationLink(destination: SettingsCurrencyView()) {
          SettingsNativeRow(title: "Valuta", systemImage: "eurosign.circle.fill", tint: .green, value: currency)
        }
        NavigationLink(destination: AccountListView()) {
          SettingsNativeRow(title: "Conti", systemImage: "building.columns.fill", tint: .blue, value: "Gestisci i tuoi conti")
        }
        NavigationLink(destination: WalletAutomationView()) {
          SettingsNativeRow(title: "Automazione Wallet", systemImage: "wallet.pass.fill", tint: .orange, value: "Comandi Rapidi")
        }
        NavigationLink(destination: SettingsWeekStartView()) {
          SettingsNativeRow(title: "Week Starts On", systemImage: "calendar.badge.clock", tint: .red, value: firstWeekdayValue)
        }
      }

      Section("Monitoraggio") {
        Toggle(isOn: incomeTrackingBinding) {
          SettingsNativeLabel(title: "Monitoraggio entrate", systemImage: "banknote.fill", tint: .green)
        }
      }

      Section("Sicurezza") {
        Toggle(isOn: appLockBinding) {
          SettingsNativeLabel(title: "Autenticazione", systemImage: "faceid", tint: .blue)
        }
      }

      Section("Aspetto") {
        Picker(selection: $colourScheme) {
          Text("Sistema").tag(0)
          Text("Chiaro").tag(1)
          Text("Scuro").tag(2)
        } label: {
          SettingsNativeLabel(title: "Tema", systemImage: "circle.lefthalf.filled", tint: .gray)
        }
        .pickerStyle(.menu)
        Toggle(isOn: $showCents) {
          SettingsNativeLabel(title: "Mostra centesimi", systemImage: "centsign.circle.fill", tint: .teal)
        }
        NavigationLink(destination: SettingsUpcomingView()) {
          SettingsNativeRow(title: "Movimenti futuri", systemImage: "clock.arrow.circlepath", tint: .orange, value: upcomingValue)
        }
        Toggle(isOn: $showExpenseOrIncomeSign) {
          SettingsNativeLabel(title: "Mostra simbolo +/-", systemImage: "plus.forwardslash.minus", tint: .pink)
        }
        Toggle(isOn: $animated) {
          SettingsNativeLabel(title: "Grafici animati", systemImage: "hare.fill", tint: .mint)
        }
      }

      Section("Dati") {
        NavigationLink(destination: SettingsCategoryView()) {
          SettingsNativeRow(title: "Categorie", systemImage: "rectangle.grid.2x2.fill", tint: .blue)
        }
        NavigationLink(destination: SettingsCloudView()) {
          SettingsNativeRow(title: "iCloud", systemImage: "icloud.fill", tint: .blue, value: iCloudValue)
        }
        Button { showImportGuide = true } label: {
          SettingsNativeLabel(title: "Importa dati", systemImage: "arrow.down.circle.fill", tint: .green)
        }
        Button { exportData() } label: {
          SettingsNativeLabel(title: "Esporta dati", systemImage: "arrow.up.circle.fill", tint: .orange)
        }
        NavigationLink(destination: SettingsEraseView()) {
          SettingsNativeLabel(title: "Elimina dati", systemImage: "trash.fill", tint: .red)
        }
      }

      Section("Avanzate") {
        NavigationLink(destination: SettingsHapticsView()) {
          SettingsNativeRow(title: "Feedback aptico", systemImage: "hand.tap.fill", tint: .pink, value: hapticValue)
        }
        NavigationLink(destination: SettingsGoofyView()) {
          SettingsNativeLabel(title: "Laboratorio funzioni", systemImage: "flame.fill", tint: .orange)
        }
      }

    }
    .listStyle(.insetGrouped)
    .navigationTitle("Impostazioni")
    .navigationBarTitleDisplayMode(.large)
    .dynamicTypeSize(...DynamicTypeSize.accessibility5)
    .onChange(of: currency) { _ in WidgetCenter.shared.reloadAllTimelines() }
    .onChange(of: firstWeekday) { _ in WidgetCenter.shared.reloadAllTimelines() }
    .onChange(of: showCents) { _ in WidgetCenter.shared.reloadAllTimelines() }
  }

  private var notificationValue: String {
    guard showNotifications else { return "Disattivate" }
    switch option {
    case 1: return "Mattina"
    case 2: return "Sera"
    default: return "Personalizzate"
    }
  }

  private var firstWeekdayValue: String {
    firstWeekday == 1 ? "Domenica" : "Lunedì"
  }

  private var upcomingValue: String {
    showUpcoming ? "Mostrati" : "Nascosti"
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
    Sa7totIconTile(systemName: Sa7totSymbolResolver.resolved(systemImage), tint: tint, size: 30)
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

struct SettingsCategoryView: View {
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

  var body: some View {
    CategoryView(mode: .settings, income: false)
      .navigationTitle("Categorie")
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarBackButtonHidden(false)
      .background(NativeTabBarVisibility(isHidden: true))
      .background(Color.PrimaryBackground)
      .onDisappear {
        TabBarVisibilityViewController.setAllTabBarsHidden(false)
      }
  }
}

private struct NativeTabBarVisibility: UIViewControllerRepresentable {
  let isHidden: Bool

  func makeUIViewController(context: Context) -> TabBarVisibilityViewController {
    let controller = TabBarVisibilityViewController()
    controller.isHidden = isHidden
    return controller
  }

  func updateUIViewController(_ controller: TabBarVisibilityViewController, context: Context) {
    controller.isHidden = isHidden
    controller.applyVisibility()
  }

  static func dismantleUIViewController(_ controller: TabBarVisibilityViewController, coordinator: ()) {
    controller.isHidden = false
    controller.applyVisibility()
  }
}

private final class TabBarVisibilityViewController: UIViewController {
  var isHidden = false

  override func didMove(toParent parent: UIViewController?) {
    super.didMove(toParent: parent)
    applyVisibility()
  }

  func applyVisibility() {
    tabBarController?.tabBar.isHidden = isHidden
  }

  static func setAllTabBarsHidden(_ hidden: Bool) {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)

    for window in windows where window.isKeyWindow || window.windowLevel == .normal {
      setTabBarsHidden(in: window.rootViewController, hidden: hidden)
    }
  }

  private static func setTabBarsHidden(in controller: UIViewController?, hidden: Bool) {
    guard let controller else { return }

    if let tabBarController = controller as? UITabBarController {
      tabBarController.tabBar.isHidden = hidden
    }

    for child in controller.children {
      setTabBarsHidden(in: child, hidden: hidden)
    }

    setTabBarsHidden(in: controller.presentedViewController, hidden: hidden)
  }
}
