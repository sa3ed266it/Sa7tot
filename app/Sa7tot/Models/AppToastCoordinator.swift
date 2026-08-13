import Combine
import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppToastCoordinator: ObservableObject {
    @Published private(set) var current: AppToast?

    private let visibleDurationNanoseconds: UInt64
    private let feedbackEnabled: Bool
    private var dismissalTask: Task<Void, Never>?

    init(visibleDuration: TimeInterval = 2.2, feedbackEnabled: Bool = true) {
        visibleDurationNanoseconds = UInt64(max(visibleDuration, 0) * 1_000_000_000)
        self.feedbackEnabled = feedbackEnabled
    }

    func show(kind: AppToast.Kind, amount: String = "") {
        dismissalTask?.cancel()

        let toast = AppToast(kind: kind, amount: amount)
        withAnimation(.easeOut(duration: 0.25)) {
            current = toast
        }

        if feedbackEnabled {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(
                notification: .announcement,
                argument: toast.accessibilityAnnouncement
            )
        }

        let toastID = toast.id
        let duration = visibleDurationNanoseconds
        dismissalTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: duration)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            self?.dismiss(id: toastID)
        }
    }

    func showError(titleKey: String = "error.mutation.delete.title", error: AppError) {
        let presentation = AppErrorPresentationPolicy.blockingPresentation(for: error)
        showError(titleKey: titleKey, messageKey: presentation.messageKey)
    }

    func showError(titleKey: String, messageKey: String) {
        dismissalTask?.cancel()

        let toast = AppToast(kind: .error(titleKey: titleKey, messageKey: messageKey), amount: "")
        withAnimation(.easeOut(duration: 0.25)) {
            current = toast
        }

        if feedbackEnabled {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.warning)
        }

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(
                notification: .announcement,
                argument: toast.accessibilityAnnouncement
            )
        }

        let toastID = toast.id
        let duration = visibleDurationNanoseconds
        dismissalTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: duration)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            self?.dismiss(id: toastID)
        }
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        withAnimation(.easeInOut(duration: 0.20)) {
            current = nil
        }
    }

    private func dismiss(id: UUID) {
        guard current?.id == id else { return }
        dismissalTask = nil
        withAnimation(.easeInOut(duration: 0.20)) {
            current = nil
        }
    }
}
