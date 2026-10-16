import Foundation

/// Which tab the panel is showing.
///
/// A closed set rather than a `TabView` selection or a `NavigationStack`: both of those behave
/// in undocumented ways inside a content-sized `NSPanel`, and either is the change most likely
/// to bring back the layout recursion the panel's fixed size exists to prevent. An enum also
/// makes "no tab" and "two tabs" unrepresentable.
nonisolated enum PanelTab: Sendable, Hashable, CaseIterable {
    case keys
    case hosts
    case newKey

    /// The tab the panel opens on after launch.
    static let initial = PanelTab.keys

    var title: String {
        switch self {
        case .keys: "Keys"
        case .hosts: "Hosts"
        case .newKey: "New Key"
        }
    }
}
