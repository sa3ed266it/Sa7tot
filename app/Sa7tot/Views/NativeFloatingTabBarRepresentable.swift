//
//  NativeFloatingTabBarRepresentable.swift
//  Sa7tot
//

import SwiftUI
import UIKit

struct NativeFloatingTabBarRepresentable: UIViewRepresentable {
    @Binding var currentTab: String
    var isVisible: Bool
    var onAdd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> NativeFloatingTabBarView {
        NativeFloatingTabBarView(
            onTabSelected: { index in
                context.coordinator.selectTab(at: index)
            },
            onAdd: {
                context.coordinator.addMovement()
            }
        )
    }

    func updateUIView(_ uiView: NativeFloatingTabBarView, context: Context) {
        context.coordinator.parent = self
        uiView.setSelectedTab(currentTab)
        uiView.setVisible(isVisible, animated: true)
    }

    final class Coordinator {
        var parent: NativeFloatingTabBarRepresentable

        init(_ parent: NativeFloatingTabBarRepresentable) {
            self.parent = parent
        }

        func selectTab(at index: Int) {
            guard let tab = NativeFloatingTabBarView.tabIdentifiers[safe: index] else { return }
            guard parent.currentTab != tab else { return }

            DispatchQueue.main.async {
                self.parent.currentTab = tab
            }
        }

        func addMovement() {
            DispatchQueue.main.async {
                self.parent.onAdd()
            }
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// Kept as a shared SwiftUI button style for existing non-navigation screens.
struct BouncyButton: ButtonStyle {
    var duration: Double
    var scale: Double

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: duration), value: configuration.isPressed)
    }
}
