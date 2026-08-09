enum Sa7totMainTabConfiguration {
    static let movements = "Log"
    static let subscriptions = "Subscriptions"
    static let settings = "Settings"
    static let search = "Search"
    static let ordered = [movements, subscriptions, settings]
    static var trailingAddTitle: String { AppLocalization.string("action.addMovement") }
}
