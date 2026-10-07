import Foundation

/// The project's spacing scale.
///
/// Namespaced rather than a set of top-level constants, so a call site reads `Spacing.regular`
/// and nothing has to guess what a bare `regular` refers to. Components take their spacing from
/// here instead of writing a number, which is what makes a density change one edit.
enum Spacing {

    /// Between a glyph and the text it belongs to.
    static let hairline: CGFloat = 2

    /// Between a control and the message explaining it.
    static let tight: CGFloat = 4

    /// Inside a control, between its chrome and its content.
    static let snug: CGFloat = 6

    /// Between sibling rows in a panel.
    static let regular: CGFloat = 10

    /// Between sections, and between a panel's edge and its content.
    static let loose: CGFloat = 16

    /// The scale in ascending order.
    ///
    /// Exists so the ordering is assertable: a scale whose names stop matching its magnitudes is
    /// worse than no scale, because call sites pick by name.
    static let ascending: [CGFloat] = [hairline, tight, snug, regular, loose]
}
