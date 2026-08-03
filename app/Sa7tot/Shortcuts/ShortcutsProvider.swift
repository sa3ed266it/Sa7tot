//
//  ShortcutsProvider.swift
//  sa7tot
//
//  Created by Rafael Soh on 5/8/23.
//

import AppIntents
import Foundation

@available(iOS 16.4, *)
struct Sa7totShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewTransactionIntent(),
            phrases: ["Registra un nuovo movimento in \(.applicationName)"],
            systemImageName: "books.vertical.fill"
        )
        AppShortcut(
            intent: GetInsightsIntent(),
            phrases: ["Mostra le statistiche in \(.applicationName)"],
            systemImageName: "plusminus.circle.fill"
        )
        AppShortcut(
            intent: BudgetIntent(),
            phrases: ["Mostra lo stato dei miei budget in \(.applicationName)"],
            systemImageName: "circle.grid.2x2.fill"
        )
        AppShortcut(
            intent: LogWalletExpenseIntent(),
            phrases: [
                "Registra una spesa in \(.applicationName)",
                "Registra spesa da Wallet in \(.applicationName)",
                "Aggiungi un pagamento Wallet a \(.applicationName)"
            ],
            systemImageName: "wallet.pass.fill"
        )
    }
}
