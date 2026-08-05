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
        HStack(spacing: 8) {
            Image(systemName: income ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
                .padding(5)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.23), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 3)

            VStack(alignment: .leading, spacing: 0) {
                Text(income ? "Entrate" : "Spese")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .foregroundColor(Color.SubtitleText)

                Text(amountString)
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 7)
        .frame(minHeight: 64)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(income ? "Entrate" : "Spese")
        .accessibilityValue(showOverlay ? "Selezionato, \(amountString)" : amountString)
        .onTapGesture {
            self.action()
        }
        .background(color.opacity(showOverlay ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if showOverlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(color, lineWidth: 1.3)
            }
        }
    }
}
