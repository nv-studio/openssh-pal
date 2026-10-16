import SwiftUI

/// Requires a destructive button to be activated twice before the caller's action runs, and
/// names what is about to happen in between.
///
/// A `PrimitiveButtonStyle` rather than a `ButtonStyle`, because only the primitive protocol
/// exposes `trigger()` — the ability to *withhold* activation, which is the whole mechanism here.
///
/// No dialog is presented. The menu bar panel has no key window and dismisses when the user
/// clicks outside it, so a modal attached to it is at best unreliable; a two-step inline
/// affordance never leaves the panel and suits a popover better anyway.
///
/// The title and message are the **caller's**, so a confirmation can name the specific thing it
/// is about to destroy rather than asking "are you sure?" about nothing in particular. This layer
/// owns the gate and knows nothing about what is behind it.
///
/// There is deliberately no "do not ask again" affordance. A remembered preference would let a
/// caller be bypassed by a decision the user made about something else.
///
/// Apply this to the specific destructive button, **not** at the scene root: a primitive style
/// replaces activation for every descendant button, including the one this style builds.
struct ConfirmingButtonStyle: PrimitiveButtonStyle {

    /// What is about to happen, in a few words.
    let title: String

    /// What it will cost, including anything irreversible about it.
    let message: String

    func makeBody(configuration: Configuration) -> some View {
        Gate(configuration: configuration, title: title, message: message)
    }

    private struct Gate: View {
        let configuration: PrimitiveButtonStyleConfiguration
        let title: String
        let message: String

        /// The one piece of component-owned state in this layer.
        ///
        /// Its only effect is whether the caller's closure runs; it never alters the caller's
        /// data, and it is discarded when the panel closes — which is the safe default for a
        /// half-confirmed destructive action. Recorded as a deliberate exception to the
        /// "components own no state" rule rather than left for a reviewer to discover.
        @State private var awaitingConfirmation = false

        var body: some View {
            if configuration.role == .destructive {
                destructive
            } else {
                // A non-destructive button is passed straight through: the gate exists for
                // actions that cannot be undone.
                Button(role: configuration.role) {
                    configuration.trigger()
                } label: {
                    configuration.label
                }
                .buttonStyle(.automatic)
            }
        }

        @ViewBuilder private var destructive: some View {
            if awaitingConfirmation {
                VStack(alignment: .leading, spacing: Spacing.snug) {
                    Text(title)
                        .font(Typography.fieldLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(message)
                        .font(Typography.fieldMessage)
                        .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))
                        .lineLimit(3, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: Spacing.snug) {
                        // Declining must leave the action uninvoked, which is why the gate
                        // closes without calling `trigger()`.
                        Button("Cancel") { awaitingConfirmation = false }
                            .accessibilityLabel("Cancel: \(title)")

                        Button(role: .destructive) {
                            configuration.trigger()
                            awaitingConfirmation = false
                        } label: {
                            Label("Confirm", systemImage: StatusRole.warning.symbolName)
                        }
                        .accessibilityLabel("Confirm: \(title)")
                    }
                }
                // Resets the *primitive* slot so the buttons this style builds do not receive
                // this same style again and recurse. The appearance slot is untouched, so
                // `PanelButtonStyle` still applies.
                .buttonStyle(.automatic)
            } else {
                Button(role: .destructive) {
                    awaitingConfirmation = true
                } label: {
                    configuration.label
                }
                .buttonStyle(.automatic)
            }
        }
    }
}

extension PrimitiveButtonStyle where Self == ConfirmingButtonStyle {

    /// Gates a destructive action behind a second activation that names what it will do.
    ///
    /// - Parameters:
    ///   - title: what is about to happen.
    ///   - message: what it will cost, including anything irreversible.
    static func confirming(title: String, message: String) -> ConfirmingButtonStyle {
        ConfirmingButtonStyle(title: title, message: message)
    }
}

#Preview("Destructive needs two activations and names what it will do") {
    VStack(alignment: .leading, spacing: Spacing.regular) {
        Button("Delete key", role: .destructive) {}
            .buttonStyle(.confirming(
                title: "Delete id_ed25519?",
                message: "id_ed25519 and id_ed25519.pub are removed permanently. This cannot be undone."
            ))

        Button("Reveal", role: nil) {}
            .buttonStyle(.confirming(title: "unused", message: "unused"))
    }
    .buttonStyle(.panelPlain)
    .padding(Spacing.loose)
    .frame(width: PanelMetrics.width)
}
