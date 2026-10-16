import SwiftUI

/// How every button in the app looks.
///
/// Applied once at the scene root, so a plain `Button` written anywhere below inherits it. That
/// is the reason this is a `ButtonStyle` and not a `PanelButton` view: a wrapper only reaches the
/// call sites that remembered to use it, while a style reaches the ones written by someone who
/// never read this file.
struct PanelButtonStyle: ButtonStyle {

    /// How much the button asks for attention. Distinguished by fill and weight as well as
    /// colour, so the difference survives a user who cannot separate the hues.
    enum Emphasis: Sendable {
        case prominent
        case plain
    }

    let emphasis: Emphasis

    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration, emphasis: emphasis)
    }

    /// A nested `View`, and that is load-bearing.
    ///
    /// `ButtonStyleConfiguration` carries `isPressed` and `role` but **no** enabled flag, so the
    /// disabled appearance has to come from the environment. A `ButtonStyle` is not a `View`, so
    /// an `@Environment` property declared on the style itself is never reinstalled when the
    /// environment changes — it would silently report `true` forever and every button would look
    /// enabled. Reading it inside a real `View` is what makes it track.
    private struct Chrome: View {
        let configuration: ButtonStyleConfiguration
        let emphasis: Emphasis

        @Environment(\.isEnabled) private var isEnabled

        private var isDestructive: Bool {
            configuration.role == .destructive
        }

        private var foregroundRole: ColorRole {
            switch (emphasis, isDestructive) {
            case (_, true): .destructive
            case (.prominent, false): .primaryText
            case (.plain, false): .primaryText
            }
        }

        var body: some View {
            configuration.label
                .font(Typography.control)
                .fontWeight(emphasis == .prominent ? .semibold : .regular)
                .foregroundStyle(ColorRoleAppearance.style(for: foregroundRole))
                .padding(.horizontal, Spacing.regular)
                .padding(.vertical, Spacing.snug)
                .background(fill, in: .rect(cornerRadius: Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .strokeBorder(
                            ColorRoleAppearance.style(for: isDestructive ? .destructive : .fieldBorder),
                            lineWidth: 1
                        )
                        .opacity(emphasis == .plain ? 1 : 0)
                }
                .opacity(opacity)
        }

        private var fill: AnyShapeStyle {
            switch emphasis {
            case .prominent:
                // Wrapping the faded style keeps both branches the same type. `opacity` on a
                // `ShapeStyle` yields a concrete style, which is what `AnyShapeStyle` can take.
                AnyShapeStyle(
                    ColorRoleAppearance.style(for: isDestructive ? .destructive : .prominent)
                        .opacity(0.18)
                )
            case .plain:
                AnyShapeStyle(.clear)
            }
        }

        /// Pressed and disabled are both expressed here so they compose rather than fight.
        private var opacity: Double {
            if isEnabled == false { return 0.4 }
            return configuration.isPressed ? 0.7 : 1
        }
    }
}

extension ButtonStyle where Self == PanelButtonStyle {

    /// The one action a surface wants the user to take.
    static var panelProminent: PanelButtonStyle { PanelButtonStyle(emphasis: .prominent) }

    /// Everything else.
    static var panelPlain: PanelButtonStyle { PanelButtonStyle(emphasis: .plain) }
}

#Preview("Button emphases and states") {
    VStack(alignment: .leading, spacing: Spacing.regular) {
        Button("Prominent") {}.buttonStyle(.panelProminent)
        Button("Plain") {}.buttonStyle(.panelPlain)
        Button("Disabled") {}.buttonStyle(.panelPlain).disabled(true)
        Button("Delete key", role: .destructive) {}.buttonStyle(.panelPlain)
        Button("Destructive prominent", role: .destructive) {}.buttonStyle(.panelProminent)
    }
    .padding(Spacing.loose)
    .frame(width: 320)
}
