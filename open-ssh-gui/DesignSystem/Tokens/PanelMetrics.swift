import Foundation

/// Fixed dimensions of the menu bar panel.
///
/// Exists because the panel sizes itself to its content: any region whose height could vary needs
/// an explicit bound, and a bound written as a literal at the call site is a bound nobody can find
/// again. Added rather than reusing `Spacing`, since a width is not a gap.
enum PanelMetrics {

    /// The panel's width. Every surface uses the same one, so a component laid out for one panel
    /// fits all of them.
    static let width: CGFloat = 320

    /// The tallest a scrolling region inside the panel may be.
    static let maximumScrollHeight: CGFloat = 360
}
