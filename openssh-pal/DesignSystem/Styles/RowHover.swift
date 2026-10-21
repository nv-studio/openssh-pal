import SwiftUI

/// Tints a row of a collection while the pointer is over it, so the row a click will select is
/// visible before the click, and while it is selected.
///
/// The tint is drawn behind the row itself, which fills the full width of the collection, so it
/// covers the whole row and not just the text inside it. A `ViewModifier` for the same reason as
/// `RowChrome`: `ListStyle` cannot be implemented without private SDK interface.
struct RowHover: ViewModifier {

    let isSelected: Bool

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.regular)
            .padding(.vertical, Spacing.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ColorRoleAppearance.style(for: isSelected ? .fieldBackground : .rowHover)
                    .opacity(isSelected || isHovered ? 1 : 0),
                in: .rect(cornerRadius: Radius.control)
            )
            // The whole row is the target, so the hand and the tint never drop out between rows.
            .contentShape(.rect)
            .onHover { isHovered = $0 }
            // A click selects the row, so it gets the same cursor as a button.
            .pressablePointer()
    }
}

extension View {

    /// Tints one row of a collection while the pointer is over it, and while it is selected.
    func rowHover(isSelected: Bool = false) -> some View {
        modifier(RowHover(isSelected: isSelected))
    }
}
