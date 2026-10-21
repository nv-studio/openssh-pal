import Foundation

/// Fixed dimensions of the menu bar panel.
///
/// Exists because the panel sizes itself to its content: any region whose height could vary needs
/// an explicit bound, and a bound written as a literal at the call site is a bound nobody can find
/// again. Added rather than reusing `Spacing`, since a width is not a gap.
enum PanelMetrics {

    /// The panel's outside width. One value for every panel, so a component laid out for one
    /// fits all of them. A surface inside the gutter uses `contentWidth`.
    static let width: CGFloat = 320

    /// The margin between the panel's edge and what sits directly on it: the two containers
    /// and Quit. One value on every side, so the margin under Quit matches the one above the
    /// tab bar.
    static let edgeInset: CGFloat = 12

    /// The padding between a container's edge and its content.
    static let containerPadding: CGFloat = 12

    /// The gutter between the panel's edge and a surface's content: the edge inset plus the
    /// padding of the container the surface sits in.
    ///
    /// Its own number rather than `Spacing.loose`, because `contentWidth` has to be derived
    /// from the same value, and a panel's gutter is not a gap between siblings.
    static let contentInset: CGFloat = edgeInset + containerPadding

    /// The width a surface is laid out at: the panel's width less the gutter on both sides.
    ///
    /// Surfaces state this rather than `width`, and the difference is visible rather than
    /// pedantic. `padding` followed by `frame(width:)` proposes the narrower width to the
    /// content but *reports* the clamped one, so a surface insisting on the full `width` was
    /// drawn edge to edge while the divider and Quit beneath it were inset — the gutter
    /// cancelled for exactly the regions that fill the panel.
    static let contentWidth: CGFloat = width - contentInset * 2

    /// The tallest a scrolling region inside the panel may be.
    static let maximumScrollHeight: CGFloat = 360

    /// The panel's exact height.
    ///
    /// Exact rather than a maximum, and that is the point. `menuBarExtraStyle(.window)` sizes
    /// the panel to its content, so a height that could settle after the first layout pass is
    /// what produces `_NSDetectedLayoutRecursion` — and a `ScrollView` inside a
    /// content-sized panel is reported to lay out correctly on the first open and collapse on
    /// later ones. With every region fixed, neither is reachable.
    ///
    /// The sum of its regions with nothing left over, so no slack collects under Quit: the
    /// edge inset top and bottom, the tab bar's container, the body's container, the footer
    /// holding Quit, and a gap between each.
    static let height: CGFloat =
        edgeInset * 2 + tabContainerHeight + bodyContainerHeight + footerHeight + Spacing.regular * 2

    /// The height of the tab bar at the top of the panel.
    ///
    /// A tab's title, the gap to its underline and the underline come to about 25 points at
    /// the default text size; the rest is room for them to grow with the user's text size
    /// without moving the surface below.
    static let tabBarHeight: CGFloat = 28

    /// The thickness of the line under the selected tab.
    static let tabUnderlineHeight: CGFloat = 2

    /// The height of the container around the tab bar.
    static let tabContainerHeight: CGFloat = tabBarHeight + Spacing.snug * 2

    /// The height of the container around the selected tab's surface and its notice.
    static let bodyContainerHeight: CGFloat =
        surfaceHeight + Spacing.regular + noticeHeight + containerPadding * 2

    /// The height of the footer holding Quit.
    ///
    /// Measured, not guessed: the button renders 24 points tall at the default and the largest
    /// text size alike, since a macOS push button does not scale with Dynamic Type. Quit is
    /// pinned to the footer's bottom, so if that ever changes the margin beneath it stays
    /// `edgeInset` and the difference shows above it instead.
    static let footerHeight: CGFloat = 24

    /// The exact height each panel surface fills, so no surface is content-sized.
    ///
    /// One value for every surface: the list and the create form are the same size, which is
    /// what keeps the panel from changing size when the route changes.
    ///
    /// Measured, not guessed. At the default text size the key list surface wants 438 points
    /// and the create form 383, so this is the taller of the two plus a little headroom. The
    /// previous 420 clipped the list by 18 points. Both were re-measured after `contentInset`
    /// widened and neither moved: every text row in them is line-limited, so a narrower
    /// surface truncates rather than wrapping into a taller one. To re-measure after changing
    /// either surface, delete `height:` from that surface's own `frame` and render it with
    /// `ImageRenderer`: a bound frame reports its bound whatever is inside it, which is why
    /// the panel sizing tests cannot assert this and this comment has to.
    static let surfaceHeight: CGFloat = 448

    /// The bounded height of the key list inside its surface.
    static let keyListHeight: CGFloat = 140

    /// The bounded height of the host list inside its surface.
    ///
    /// Measured the way `surfaceHeight` describes: with twelve hosts and a load issue, the host
    /// list surface wants 355 points and the host form 443, at the default and the largest text
    /// size alike. Both fit `surfaceHeight`, the list with room for the delete confirmation to
    /// open beneath it; the form's fields scroll.
    static let hostListHeight: CGFloat = 132

    /// The height reserved for the selected host's attributes, keys and file.
    ///
    /// Reserved whether or not anything is selected, so selecting a host does not move the
    /// controls beneath it.
    static let hostDetailHeight: CGFloat = 112

    /// The bounded height of the key picker inside the host form.
    static let keyPickerHeight: CGFloat = 104

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
