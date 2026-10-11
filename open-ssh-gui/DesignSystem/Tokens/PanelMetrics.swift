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

    /// The panel's exact height.
    ///
    /// Exact rather than a maximum, and that is the point. `menuBarExtraStyle(.window)` sizes
    /// the panel to its content, so a height that could settle after the first layout pass is
    /// what produces `_NSDetectedLayoutRecursion` — and a `ScrollView` inside a
    /// content-sized panel is reported to lay out correctly on the first open and collapse on
    /// later ones. With every region fixed, neither is reachable.
    static let height: CGFloat = 548

    /// The exact height each panel surface fills, so no surface is content-sized.
    ///
    /// One value for every surface: the list and the create form are the same size, which is
    /// what keeps the panel from changing size when the route changes.
    static let surfaceHeight: CGFloat = 420

    /// The bounded height of the key list inside its surface.
    static let keyListHeight: CGFloat = 140

    /// The height reserved for the selected key's attributes.
    ///
    /// Reserved whether or not anything is selected, so selecting a key does not move the
    /// controls beneath it.
    static let keyDetailHeight: CGFloat = 118

    /// The height reserved for a field's validation message.
    ///
    /// Reserved whether or not there is a message, so showing one never changes a field's
    /// height. A token rather than a literal at each call site, so the two fields that
    /// reserve it cannot drift apart.
    static let fieldMessageHeight: CGFloat = 14

    /// The height reserved for the outcome of the last operation.
    ///
    /// Reserved whether or not there is an outcome to report, so a confirmation appearing
    /// never changes the panel's height.
    static let noticeHeight: CGFloat = 38
}
