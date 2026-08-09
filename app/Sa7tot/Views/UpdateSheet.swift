//
//  UpdateSheet.swift
//  sa7tot
//
//  Created by Rafael Soh on 13/9/23.
//

import Foundation
import SwiftUI

struct WelcomeSheetFeatureRow: Hashable {
    let icon: String
    let headerKey: String
    let subtitleKey: String
}

struct UpdateAlert: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var systemColorScheme

    @State private var offset: CGFloat = 0

    @AppStorage("bottomEdge", store: UserDefaults(suiteName: "group.com.saied.sa7tot")) var bottomEdge: Double = 15

    @State var opacity = 0.0

    let welcomeFeatures = [
        WelcomeSheetFeatureRow(icon: "appclip", headerKey: "update.feature.shortcuts", subtitleKey: "update.feature.shortcutsDescription"),
        WelcomeSheetFeatureRow(icon: "arrow.down.doc.fill", headerKey: "update.feature.import", subtitleKey: "update.feature.importDescription"),
        WelcomeSheetFeatureRow(icon: "sun.haze.fill", headerKey: "update.feature.future", subtitleKey: "update.feature.futureDescription"),
        WelcomeSheetFeatureRow(icon: "app.gift.fill", headerKey: "update.feature.icons", subtitleKey: "update.feature.iconsDescription"),
        WelcomeSheetFeatureRow(icon: "circle.grid.2x2.fill", headerKey: "update.feature.screens", subtitleKey: "update.feature.screensDescription"),
        WelcomeSheetFeatureRow(icon: "swatchpalette.fill", headerKey: "update.feature.colors", subtitleKey: "update.feature.colorsDescription"),
        WelcomeSheetFeatureRow(icon: "exclamationmark.octagon.fill", headerKey: "update.feature.messages", subtitleKey: "update.feature.messagesDescription"),
    ]

    var body: some View {
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

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "star.fill")
                            .font(.system(.callout, design: .rounded))
//                            .font(.system(size: 16))
                        Text(AppLocalization.key("update.title"))
                            .font(.system(.title2, design: .rounded).weight(.medium))
//                            .font(.system(size: 22, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.PrimaryText)

                    Text(verbatim: AppLocalization.format("update.version", UIApplication.appVersion ?? "", UIApplication.buildNumber ?? "", AppLocalization.string("update.releaseDate")))
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
//                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.SubtitleText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topTrailing) {
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
//                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(Color.AppSecondarySurface, in: Circle())
                            .contentShape(Circle())
                    }
                    .offset(x: 5, y: -5)
                }
                .padding(.bottom, 15)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(welcomeFeatures, id: \.self) { row in
                            HStack(alignment: .top, spacing: 15) {
                                Image(systemName: row.icon)
                                    .font(.system(.title2, design: .rounded))
//                                    .font(.system(size: 24, weight: .regular))
                                    .foregroundColor(Color.SubtitleText)
                                    .frame(width: 35, alignment: .leading)
                                    .offset(y: 2)

                                VStack(alignment: .leading, spacing: 3.5) {
                                    Text(AppLocalization.key(row.headerKey))
                                        .font(.system(.body, design: .rounded).weight(.medium))
//                                        .font(.system(size: 18, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.PrimaryText)

                                    Text(AppLocalization.key(row.subtitleKey))
                                        .font(.system(.subheadline, design: .rounded).weight(.medium))
//                                        .font(.system(size: 16, weight: .regular, design: .rounded))
//                                            .lineSpacing(0.6)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .foregroundColor(Color.SubtitleText)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .frame(height: 300)

                (Text(AppLocalization.key("update.thanksPrefix")) + Text(makeAttributedString()) + Text(AppLocalization.key("update.thanksSuffix")))
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundColor(Color.SubtitleText)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 13).fill(Color.AppPageBackground).shadow(color: systemColorScheme == .dark ? Color.clear : Color.gray.opacity(0.25), radius: 6))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(systemColorScheme == .dark ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
            .offset(y: offset)
            .padding(.horizontal, 17)
            .padding(.bottom, bottomEdge == 0 ? 13 : bottomEdge)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .edgesIgnoringSafeArea(.all)
        .background(BackgroundBlurView())
    }

    func makeAttributedString() -> AttributedString {
        var string = AttributedString("Yumi")
        string.foregroundColor = Color.PrimaryText
        string.link = URL(string: "https://yumiizumi.com/")

        return string
    }
}
