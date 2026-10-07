import SwiftUI

/// Requires a destructive button to be activated twice before the caller's action runs.
///
/// A `PrimitiveButtonStyle` rather than a `ButtonStyle`, because only the primitive protocol
/// exposes `trigger()` — the ability to *withhold* activation, which is the whole mechanism here.
///
/// No dialog is presented. The menu bar panel has no key window and dismisses when the user
/// clicks outside it, so a modal attached to it is at best unreliable; a two-step inline
/// affordance never leaves the panel and suits a popover better anyway.
///
/// Apply this to the specific destructive button, **not** at the scene root: a primitive style
/// replaces activation for every descendant button, including the one this style builds.
struct ConfirmingButtonStyle: PrimitiveButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        Gate(configuration: configuration)
    }

    private struct Gate: View {
        let configuration: PrimitiveButtonStyleConfiguration

        /// The one piece of component-owned state in this layer.
        ///
        /// Its only effect is whether the caller's closure runs; it never alters the caller's
        /// data, and it is discarded when the panel closes — which is the safe default for a
        /// half-confirmed destructive action. Recorded as a deliberate exception to the
        /// "components own no state" rule rather than left for a reviewer to discover.
        @State private var awaitingConfirmation = false

        var body: some View {
            if configuration.role == .destructive {
                Button(role: .destructive) {
                    if awaitingConfirmation {
                        configuration.trigger()
                        awaitingConfirmation = false
                    } else {
                        awaitingConfirmation = true
                    }
                } label: {
                    if awaitingConfirmation {
                        Label("Confirm", systemImage: StatusRole.warning.symbolName)
                    } else {
                        configuration.label
                    }
                }
                // Resets the *primitive* slot so the button this style builds does not receive
                // this same style again and recurse. The appearance slot is untouched, so
                // `PanelButtonStyle` still applies.
                .buttonStyle(.automatic)
            } else {
                Button(role: configuration.role) {
                    configuration.trigger()
                } label: {
                    configuration.label
                }
                .buttonStyle(.automatic)
            }
        }
    }
}

extension PrimitiveButtonStyle where Self == ConfirmingButtonStyle {

    /// Gates a destructive action behind a second activation.
    static var confirming: ConfirmingButtonStyle { ConfirmingButtonStyle() }
}

#Preview("Destructive needs two activations") {
    VStack(alignment: .leading, spacing: Spacing.regular) {
        Button("Delete key", role: .destructive) {}
            .buttonStyle(.confirming)
        Button("Reveal", role: nil) {}
            .buttonStyle(.confirming)
    }
    .buttonStyle(.panelPlain)
    .padding(Spacing.loose)
    .frame(width: 320)
}
