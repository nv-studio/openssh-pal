import SwiftUI

/// The project's type scale.
///
/// Every token is built from a system text style rather than a point size, so the user's chosen
/// text size carries through without any component doing arithmetic.
enum Typography {

    /// A section's heading inside the panel.
    static let sectionHeader = Font.caption.weight(.semibold)

    /// The panel's own title.
    static let panelTitle = Font.headline

    /// A section's name in the tab bar. A step above `control`, so the sections read as the
    /// panel's top level rather than as one more row of buttons.
    static let tab = Font.title3.weight(.medium)

    /// A button or field's own text.
    static let control = Font.body

    /// The name beside a field or row.
    static let fieldLabel = Font.callout

    /// A validation message under a field.
    static let fieldMessage = Font.caption

    /// A path, a fingerprint, a configuration fragment.
    static let code = Font.system(.body, design: .monospaced)

    /// The text beside a status icon.
    static let statusMessage = Font.subheadline

    /// Every token, so their distinctness is assertable.
    ///
    /// Two tokens resolving to the same font would silently merge two roles, and the merge would
    /// only show up as a design review comment months later.
    static let all: [Font] = [
        sectionHeader, panelTitle, tab, control, fieldLabel, fieldMessage, code, statusMessage,
    ]
}
