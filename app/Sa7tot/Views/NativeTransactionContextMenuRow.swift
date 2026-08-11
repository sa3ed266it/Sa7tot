import SwiftUI
import UIKit

final class ContextMenuBackgroundEffectController {
    private weak var installedWindow: UIWindow?
    private var blurView: UIVisualEffectView?
    private var dimView: UIView?
    private var transitionID = 0
    private var backgroundObserver: NSObjectProtocol?

    init() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.removeImmediately()
        }
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        removeImmediately()
    }

    func show(on window: UIWindow, animator: UIContextMenuInteractionAnimating?) {
        if installedWindow !== window {
            removeImmediately()
        }

        transitionID += 1
        let currentTransitionID = transitionID

        let blurView: UIVisualEffectView
        let dimView: UIView
        if let existingBlurView = self.blurView, let existingDimView = self.dimView {
            blurView = existingBlurView
            dimView = existingDimView
        } else {
            let newBlurView = UIVisualEffectView(effect: nil)
            newBlurView.isUserInteractionEnabled = false
            newBlurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            newBlurView.accessibilityElementsHidden = true

            let newDimView = UIView(frame: .zero)
            newDimView.isUserInteractionEnabled = false
            newDimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            newDimView.backgroundColor = .clear
            newDimView.accessibilityElementsHidden = true

            newBlurView.contentView.addSubview(newDimView)
            newDimView.frame = newBlurView.contentView.bounds
            blurView = newBlurView
            dimView = newDimView
            self.blurView = newBlurView
            self.dimView = newDimView
        }

        installedWindow = window
        blurView.frame = window.bounds
        dimView.frame = blurView.contentView.bounds
        blurView.alpha = 1
        blurView.layer.removeAllAnimations()
        dimView.layer.removeAllAnimations()

        if blurView.superview !== window {
            window.addSubview(blurView)
        }

        let reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        let targetEffect = blurEffect(for: window, reduceTransparency: reduceTransparency)
        let targetDimColor = dimColor(for: window, reduceTransparency: reduceTransparency)

        let animations = { [weak blurView, weak dimView] in
            blurView?.effect = targetEffect
            dimView?.backgroundColor = targetDimColor
        }

        if let animator {
            animator.addAnimations(animations)
        } else {
            blurView.effect = nil
            dimView.backgroundColor = .clear
            UIView.animate(withDuration: 0.18, animations: animations)
        }
    }

    func hide(animator: UIContextMenuInteractionAnimating?) {
        guard let blurView, let dimView else { return }

        transitionID += 1
        let currentTransitionID = transitionID
        let animations = { [weak blurView, weak dimView] in
            blurView?.effect = nil
            dimView?.backgroundColor = .clear
        }
        let completion = { [weak self] in
            guard let self, self.transitionID == currentTransitionID else { return }
            self.removeImmediately()
        }

        if let animator {
            animator.addAnimations(animations)
            animator.addCompletion(completion)
        } else {
            UIView.animate(withDuration: 0.16, animations: animations) { _ in
                completion()
            }
        }
    }

    func removeImmediately() {
        transitionID += 1
        blurView?.layer.removeAllAnimations()
        dimView?.layer.removeAllAnimations()
        blurView?.removeFromSuperview()
        blurView = nil
        dimView = nil
        installedWindow = nil
    }

    private func blurEffect(for window: UIWindow, reduceTransparency: Bool) -> UIBlurEffect {
        let isLight = window.traitCollection.userInterfaceStyle == .light
        let style: UIBlurEffect.Style

        if reduceTransparency {
            style = isLight ? .systemMaterialLight : .systemMaterialDark
        } else {
            style = isLight ? .systemThinMaterialLight : .systemThinMaterialDark
        }

        return UIBlurEffect(style: style)
    }

    private func dimColor(for window: UIWindow, reduceTransparency: Bool) -> UIColor {
        let isLight = window.traitCollection.userInterfaceStyle == .light
        let opacity: CGFloat

        if reduceTransparency {
            opacity = isLight ? 0.10 : 0.18
        } else {
            opacity = isLight ? 0.06 : 0.12
        }

        return UIColor.black.withAlphaComponent(opacity)
    }
}

struct NativeTransactionContextMenuRow<Content: View>: UIViewControllerRepresentable {
    let identifier: String
    let canEdit: Bool
    let canDelete: Bool
    let editTitle: String
    let deleteTitle: String
    let content: Content
    let onEdit: () -> Void
    let onDelete: () -> Void

    func makeUIViewController(context: Context) -> NativeTransactionContextMenuRowViewController<Content> {
        NativeTransactionContextMenuRowViewController(
            identifier: identifier,
            canEdit: canEdit,
            canDelete: canDelete,
            editTitle: editTitle,
            deleteTitle: deleteTitle,
            content: content,
            onEdit: onEdit,
            onDelete: onDelete
        )
    }

    func updateUIViewController(_ controller: NativeTransactionContextMenuRowViewController<Content>, context: Context) {
        controller.update(
            identifier: identifier,
            canEdit: canEdit,
            canDelete: canDelete,
            editTitle: editTitle,
            deleteTitle: deleteTitle,
            content: content,
            onEdit: onEdit,
            onDelete: onDelete
        )
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: NativeTransactionContextMenuRowViewController<Content>, context: Context) -> CGSize? {
        uiViewController.fittingSize(for: proposal.width)
    }
}

final class NativeTransactionContextMenuRowViewController<Content: View>: UIViewController, UIContextMenuInteractionDelegate {
    private var identifier: String
    private var canEdit: Bool
    private var canDelete: Bool
    private var editTitle: String
    private var deleteTitle: String
    private var onEdit: () -> Void
    private var onDelete: () -> Void
    private let hostingController: UIHostingController<Content>
    private let backgroundEffectController = ContextMenuBackgroundEffectController()

    init(identifier: String, canEdit: Bool, canDelete: Bool, editTitle: String, deleteTitle: String, content: Content, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.identifier = identifier
        self.canEdit = canEdit
        self.canDelete = canDelete
        self.editTitle = editTitle
        self.deleteTitle = deleteTitle
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.hostingController = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        view.isOpaque = false
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)

        view.addInteraction(UIContextMenuInteraction(delegate: self))
    }

    func update(identifier: String, canEdit: Bool, canDelete: Bool, editTitle: String, deleteTitle: String, content: Content, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.identifier = identifier
        self.canEdit = canEdit
        self.canDelete = canDelete
        self.editTitle = editTitle
        self.deleteTitle = deleteTitle
        self.onEdit = onEdit
        self.onDelete = onDelete
        hostingController.rootView = content
    }

    @available(iOS 16.0, *)
    func fittingSize(for width: CGFloat?) -> CGSize? {
        guard let width else { return nil }
        return hostingController.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard canEdit || canDelete else { return nil }
        return UIContextMenuConfiguration(identifier: identifier as NSString, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu(title: "", children: []) }

            var actions: [UIMenuElement] = []
            if self.canEdit {
                let edit = UIAction(title: self.editTitle, image: UIImage(systemName: "pencil")) { [weak self] _ in
                    self?.onEdit()
                }
                actions.append(edit)
            }
            if self.canDelete {
                let delete = UIAction(title: self.deleteTitle, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    self?.onDelete()
                }
                actions.append(delete)
            }

            return UIMenu(title: "", children: actions)
        }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        targetedPreview()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        targetedPreview()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        guard let window = view.window else { return }
        backgroundEffectController.show(on: window, animator: animator)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        backgroundEffectController.hide(animator: animator)
    }

    private func targetedPreview() -> UITargetedPreview {
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(rect: view.bounds)

        return UITargetedPreview(view: view, parameters: parameters)
    }

    deinit {
        backgroundEffectController.removeImmediately()
    }
}
