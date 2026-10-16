import SwiftUI

/// The chrome around an editable text field.
///
/// A `ViewModifier` rather than a `TextFieldStyle`, and that is not a preference. In the macOS 27
/// SDK `TextFieldStyle`'s only requirement is `_body(configuration:)` over an opaque
/// `_TextFieldStyleLabel` — underscored, private interface. Conforming to it would mean depending
/// on something Apple can change in a point release.
///
/// The cost of a modifier is that it must be applied per call site rather than inherited, which is
/// why every component that takes text applies it, and why the previews exist to catch a field
/// that was left bare.
struct FieldChrome: ViewModifier {

    let validation: FieldValidation

    func body(content: Content) -> some View {
        content
            // Apple's own case, then our chrome on top of it.
            .textFieldStyle(.plain)
            .font(Typography.control)
            .padding(.horizontal, Spacing.snug)
            .padding(.vertical, Spacing.tight)
            .background(
                ColorRoleAppearance.style(for: .fieldBackground),
                in: .rect(cornerRadius: Radius.control)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(
                        ColorRoleAppearance.style(for: validation.isValid ? .fieldBorder : .failure),
                        lineWidth: validation.isValid ? 1 : 1.5
                    )
            }
    }
}

extension View {

    /// Dresses a native text field in the project's chrome.
    func fieldChrome(validation: FieldValidation = .valid) -> some View {
        modifier(FieldChrome(validation: validation))
    }
}
