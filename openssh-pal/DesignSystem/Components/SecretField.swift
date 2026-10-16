import SwiftUI

/// Shows key material only once the caller has granted it.
///
/// The security property is in the *input*, not in this view: a redacted `SecretPresentation`
/// does not carry the value, so there is nothing here to leak to the screen, to an accessibility
/// label, or to a logging statement someone adds later.
///
/// Deliberately does **not** use `privacySensitive()` or `redacted(reason: .privacy)`. Those need
/// a privacy redaction reason that an app — as opposed to a widget — never sets, and neither
/// withholds the underlying string from assistive technologies. They would hide the value from the
/// user while still holding it.
struct SecretField: View {

    let label: String
    let presentation: SecretPresentation

    /// Reporting the request rather than acting on it is what keeps the reveal policy with the
    /// caller, where the key-management spec can own it.
    let onRevealRequested: () -> Void

    /// Caps how wide a placeholder gets, so a long key does not produce a wall of dots.
    private static let maximumPlaceholderLength = 24

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(label)
                .font(Typography.fieldLabel)
                .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))

            HStack(alignment: .firstTextBaseline, spacing: Spacing.snug) {
                content

                if presentation.isRevealed == false {
                    Button("Reveal") { onRevealRequested() }
                        .accessibilityLabel("Reveal \(label)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        if let value = presentation.value {
            CodeText(text: value, lineLimit: 3)
        } else {
            Text(placeholder)
                .font(Typography.code)
                .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Describes the field, never its contents — which it does not have.
                .accessibilityLabel("\(label), hidden")
        }
    }

    private var placeholder: String {
        String(
            repeating: "•",
            count: min(presentation.placeholderLength, Self.maximumPlaceholderLength)
        )
    }
}

#Preview("Redacted holds no value; revealed shows the caller's") {
    VStack(alignment: .leading, spacing: Spacing.regular) {
        SecretField(
            label: "Private key",
            presentation: .redacted(placeholderLength: 64),
            onRevealRequested: {}
        )
        SecretField(
            label: "Private key",
            presentation: .revealed("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI"),
            onRevealRequested: {}
        )
    }
    .buttonStyle(.panelPlain)
    .padding(Spacing.loose)
    .frame(width: 320)
}
