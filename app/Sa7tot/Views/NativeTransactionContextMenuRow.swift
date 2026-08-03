import SwiftUI
import UIKit

struct NativeTransactionContextMenuRow<Content: View>: UIViewControllerRepresentable {
    let identifier: String
    let canDelete: Bool
    let content: Content
    let onEdit: () -> Void
    let onDelete: () -> Void

    func makeUIViewController(context: Context) -> NativeTransactionContextMenuRowViewController<Content> {
        NativeTransactionContextMenuRowViewController(
            identifier: identifier,
            canDelete: canDelete,
            content: content,
            onEdit: onEdit,
            onDelete: onDelete
        )
    }

    func updateUIViewController(_ controller: NativeTransactionContextMenuRowViewController<Content>, context: Context) {
        controller.update(
            identifier: identifier,
            canDelete: canDelete,
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
    private var canDelete: Bool
    private var onEdit: () -> Void
    private var onDelete: () -> Void
    private let hostingController: UIHostingController<Content>

    init(identifier: String, canDelete: Bool, content: Content, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.identifier = identifier
        self.canDelete = canDelete
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

    func update(identifier: String, canDelete: Bool, content: Content, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.identifier = identifier
        self.canDelete = canDelete
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
        UIContextMenuConfiguration(identifier: identifier as NSString, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu(title: "", children: []) }

            let edit = UIAction(title: "Modifica", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.onEdit()
            }

            var actions: [UIMenuElement] = [edit]
            if self.canDelete {
                let delete = UIAction(title: "Elimina", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
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

    private func targetedPreview() -> UITargetedPreview {
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(rect: view.bounds)

        return UITargetedPreview(view: view, parameters: parameters)
    }
}
