import SwiftUI

struct AppToastView: View {
    @EnvironmentObject private var coordinator: AppToastCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayedToast: AppToast?
    @State private var phase: ToastPhase = .hidden
    @State private var isFloating = false
    @State private var transitionTask: Task<Void, Never>?

    private enum ToastPhase {
        case hidden
        case visible
        case disappearing
    }

    var body: some View {
        Group {
            if let toast = displayedToast {
                AppToastCard(toast: toast)
                    .scaleEffect(cardScale)
                    .offset(y: cardOffset)
                    .offset(y: isFloating && phase == .visible ? 1.5 : 0)
                    .opacity(cardOpacity)
                    .blur(radius: cardBlur)
                    .transition(.identity)
                    .animation(presentationAnimation, value: phase)
                    .animation(floatingAnimation, value: isFloating)
            }
        }
        .onAppear {
            synchronize(with: coordinator.current)
        }
        .onChange(of: coordinator.current?.id) { _ in
            synchronize(with: coordinator.current)
        }
        .onDisappear {
            transitionTask?.cancel()
        }
    }

    private var cardScale: CGFloat {
        guard !reduceMotion else { return 1 }
        return phase == .visible ? 1 : 0.82
    }

    private var cardOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        return phase == .visible ? 0 : -30
    }

    private var cardOpacity: Double {
        phase == .visible ? 1 : 0
    }

    private var cardBlur: CGFloat {
        guard !reduceMotion else { return 0 }
        return phase == .visible ? 0 : 4
    }

    private var presentationAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.38, dampingFraction: 0.85)
    }

    private var exitAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .easeInOut(duration: 0.30)
    }

    private var floatingAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
    }

    private func synchronize(with toast: AppToast?) {
        transitionTask?.cancel()
        transitionTask = nil

        guard let toast else {
            guard let displayedToast else { return }
            isFloating = false
            withAnimation(exitAnimation) {
                phase = .disappearing
            }

            let dismissedID = displayedToast.id
            transitionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 320_000_000)
                guard !Task.isCancelled, self.displayedToast?.id == dismissedID else { return }
                withAnimation(.linear(duration: 0.01)) {
                    self.displayedToast = nil
                    self.phase = .hidden
                }
            }
            return
        }

        guard displayedToast?.id != toast.id else { return }

        if let displayedToast {
            isFloating = false
            withAnimation(exitAnimation) {
                phase = .disappearing
            }

            let replacement = toast
            let dismissedID = displayedToast.id
            transitionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 320_000_000)
                guard !Task.isCancelled, self.displayedToast?.id == dismissedID else { return }

                self.displayedToast = replacement
                self.phase = .hidden
                withAnimation(self.presentationAnimation) {
                    self.phase = .visible
                }
                withAnimation(self.floatingAnimation) {
                    self.isFloating = true
                }
            }
        } else {
            displayedToast = toast
            phase = .hidden
            withAnimation(presentationAnimation) {
                phase = .visible
            }
            withAnimation(floatingAnimation) {
                isFloating = true
            }
        }
    }
}

private struct AppToastCard: View {
    let toast: AppToast

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !toast.amount.isEmpty {
                    Text(toast.amount)
                        .font(.system(size: 14, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .frame(minWidth: 250, idealWidth: 270, maxWidth: 300, minHeight: 58, alignment: .leading)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(toast.accessibilityAnnouncement))
    }
}
