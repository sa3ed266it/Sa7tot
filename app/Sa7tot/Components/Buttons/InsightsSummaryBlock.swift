//
//  InsightsSummaryBlock.swift
//  sa7tot
//
//  Created by Rafael Soh on 19/11/23.
//

import Foundation
import SwiftUI

struct InsightsSummaryBlockView: View {
    let income: Bool
    let amountString: String
    let showOverlay: Bool
    var action: () -> Void

    var color: Color {
        return income ? Color.IncomeGreen : Color.AlertRed
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: income ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .tertiarySystemBackground), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(income ? "Entrate" : "Spese")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                        .foregroundColor(Color.PrimaryText)

                    Text(amountString)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundColor(Color.SubtitleText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                self.action()
            }

            Capsule(style: .continuous)
                .fill(showOverlay ? color : Color.clear)
                .frame(width: 38, height: 3)
                .animation(.easeInOut(duration: 0.2), value: showOverlay)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(income ? "Entrate" : "Spese")
        .accessibilityValue(showOverlay ? "Selezionato, \(amountString)" : amountString)
    }
}
