//
//  NativeFloatingTabBarView.swift
//  Sa7tot
//

import UIKit

final class NativeFloatingTabBarView: UIView, UITabBarDelegate {
    static let tabIdentifiers = ["Log", "Insights", "Budget", "Settings"]

    private let onTabSelected: (Int) -> Void
    private let onAdd: () -> Void
    private let tabBar = UITabBar()
    private let addButton = UIButton(type: .system)
    private let tabBubble = UIView()
    private let addBubble = UIView()
    private var wantsVisible = true
    private var keyboardVisible = false

    init(onTabSelected: @escaping (Int) -> Void, onAdd: @escaping () -> Void) {
        self.onTabSelected = onTabSelected
        self.onAdd = onAdd
        super.init(frame: .zero)

        backgroundColor = .clear
        isAccessibilityElement = false
        setupViews()
        observeKeyboard()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setSelectedTab(_ identifier: String) {
        guard let item = tabBar.items?.first(where: { $0.tag == Self.tabIdentifiers.firstIndex(of: identifier) }) else {
            return
        }
        guard tabBar.selectedItem !== item else { return }
        tabBar.selectedItem = item
    }

    func setVisible(_ visible: Bool, animated: Bool) {
        wantsVisible = visible
        applyVisibility(animated: animated)
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard Self.tabIdentifiers.indices.contains(item.tag) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        onTabSelected(item.tag)
    }

    @objc private func addTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onAdd()
    }

    private func setupViews() {
        configureTabBar()
        configureAddButton()

        configureBubble(tabBubble)
        configureBubble(addBubble)
        tabBubble.addSubview(tabBar)
        addBubble.addSubview(addButton)
        addSubview(tabBubble)
        addSubview(addBubble)

        tabBar.translatesAutoresizingMaskIntoConstraints = false
        addButton.translatesAutoresizingMaskIntoConstraints = false
        tabBubble.translatesAutoresizingMaskIntoConstraints = false
        addBubble.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tabBubble.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBubble.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            tabBubble.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            addBubble.leadingAnchor.constraint(equalTo: tabBubble.trailingAnchor, constant: 14),
            addBubble.trailingAnchor.constraint(equalTo: trailingAnchor),
            addBubble.topAnchor.constraint(equalTo: tabBubble.topAnchor),
            addBubble.bottomAnchor.constraint(equalTo: tabBubble.bottomAnchor),
            addBubble.widthAnchor.constraint(equalToConstant: 56),
            tabBar.leadingAnchor.constraint(equalTo: tabBubble.leadingAnchor, constant: 2),
            tabBar.trailingAnchor.constraint(equalTo: tabBubble.trailingAnchor, constant: -2),
            tabBar.topAnchor.constraint(equalTo: tabBubble.topAnchor),
            tabBar.bottomAnchor.constraint(equalTo: tabBubble.bottomAnchor),
            addButton.centerXAnchor.constraint(equalTo: addBubble.centerXAnchor),
            addButton.centerYAnchor.constraint(equalTo: addBubble.centerYAnchor),
            addButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            addButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    private func configureTabBar() {
        tabBar.delegate = self
        // HomeView hides SwiftUI's internal TabView bar through the global
        // appearance proxy. This bridge owns a separate UITabBar instance.
        tabBar.isHidden = false
        // A centered fixed item width keeps the long Italian labels readable
        // on both the 17 Pro and the smallest supported iPhone widths.
        tabBar.itemPositioning = .centered
        tabBar.itemWidth = 68
        tabBar.itemSpacing = 0
        tabBar.isTranslucent = true
        tabBar.tintColor = .label
        tabBar.unselectedItemTintColor = .secondaryLabel

        let items: [(String, String)] = [
            ("Movimenti", "list.bullet.rectangle"),
            ("Statistiche", "chart.bar.xaxis"),
            ("Budget", "chart.pie.fill"),
            ("Impostazioni", "gearshape"),
        ]
        tabBar.items = items.enumerated().map { index, item in
            let tabItem = UITabBarItem(
                title: item.0,
                image: UIImage(systemName: item.1),
                tag: index
            )
            tabItem.accessibilityLabel = item.0
            return tabItem
        }
        tabBar.selectedItem = tabBar.items?.first

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 8.5, weight: .medium),
        ]
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 8.5, weight: .semibold),
        ]
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
    }

    private func configureAddButton() {
        addButton.accessibilityLabel = "Aggiungi movimento"
        addButton.accessibilityTraits = [.button]
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        let image = UIImage(
            systemName: "plus",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
        )

        if #available(iOS 26.0, *) {
            var configuration = UIButton.Configuration.clearGlass()
            configuration.image = image
            configuration.baseForegroundColor = .label
            addButton.configuration = configuration
        } else if #available(iOS 15.0, *) {
            var configuration = UIButton.Configuration.tinted()
            configuration.image = image
            configuration.cornerStyle = .capsule
            configuration.baseForegroundColor = .label
            configuration.baseBackgroundColor = .secondarySystemBackground
            addButton.configuration = configuration
        } else {
            addButton.setImage(image, for: .normal)
            addButton.tintColor = .label
            addButton.layer.cornerRadius = 26
            addButton.backgroundColor = .secondarySystemBackground
        }
    }

    private func configureBubble(_ bubble: UIView) {
        bubble.clipsToBounds = true
        bubble.layer.cornerRadius = 22
        bubble.layer.cornerCurve = .continuous
        bubble.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.72)

        if #available(iOS 15.0, *) {
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            blur.isUserInteractionEnabled = false
            blur.translatesAutoresizingMaskIntoConstraints = false
            bubble.insertSubview(blur, at: 0)
            NSLayoutConstraint.activate([
                blur.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
                blur.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
                blur.topAnchor.constraint(equalTo: bubble.topAnchor),
                blur.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            ])
        }
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        keyboardVisible = notification.name == UIResponder.keyboardWillShowNotification
        applyVisibility(animated: true)
    }

    private func applyVisibility(animated: Bool) {
        let visible = wantsVisible && !keyboardVisible
        let changes = {
            self.alpha = visible ? 1 : 0
            self.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 90)
            self.isUserInteractionEnabled = visible
        }

        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            changes()
            return
        }

        UIView.animate(withDuration: 0.2, animations: changes)
    }
}
