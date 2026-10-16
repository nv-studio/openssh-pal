import SwiftUI

/// The chrome around one row of a collection.
///
/// A `ViewModifier` for the same reason as `FieldChrome`: `ListStyle` declares only
/// `_makeView`/`_makeViewList` over an opaque `_ListValue`, so it cannot be implemented without
/// private SDK interface.
struct RowChrome: ViewModifier {

    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .font(Typography.control)
            .foregroundStyle(ColorRoleAppearance.style(for: .primaryText))
            .padding(.horizontal, Spacing.snug)
            .padding(.vertical, Spacing.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ColorRoleAppearance.style(for: isSelected ? .fieldBackground : .separator)
                    .opacity(isSelected ? 1 : 0),
                in: .rect(cornerRadius: Radius.control)
            )
    }
}

extension View {

    /// Dresses one row of a collection in the project's chrome.
    func rowChrome(isSelected: Bool = false) -> some View {
        modifier(RowChrome(isSelected: isSelected))
    }
}

#Preview("Field and row chrome") {
    @Previewable @State var host = "bastion"

    return VStack(alignment: .leading, spacing: Spacing.regular) {
        TextField("", text: $host).fieldChrome()
        TextField("", text: $host).fieldChrome(validation: .invalid("required"))
        VStack(spacing: Spacing.hairline) {
            Text("selected row").rowChrome(isSelected: true)
            Text("ordinary row").rowChrome()
        }
    }
    .padding(Spacing.loose)
    .frame(width: 320)
}
