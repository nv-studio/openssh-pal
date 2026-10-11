import Foundation

/// Which surface the panel is showing.
///
/// A closed pair of cases rather than a `NavigationStack`. The stack's behaviour inside a
/// content-sized `NSPanel` is undocumented and it is the change most likely to reintroduce
/// the layout recursion the panel's fixed size exists to prevent — and an enum makes "no
/// surface presented" and "two surfaces presented" unrepresentable, which a stack does not.
nonisolated enum PanelRoute: Sendable, Equatable {
    case keyList
    case newKey
}
