import SwiftUI

/// How a boolean reads in the panel.
///
/// The value stays a binding the caller owns; this style decides appearance and nothing else.
struct PanelToggleStyle: ToggleStyle {

    func makeBody(configuration: Configuration) -> some View {
        Toggle(isOn: configuration.$isOn) {
            configuration.label
                .font(Typography.fieldLabel)
                .foregroundStyle(ColorRoleAppearance.style(for: .primaryText))
        }
        // Resets the slot so the toggle built here does not receive this style again.
        .toggleStyle(.switch)
        .pressablePointer()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ToggleStyle where Self == PanelToggleStyle {
    static var panel: PanelToggleStyle { PanelToggleStyle() }
}

#Preview("Toggle driven by a caller-owned binding") {
    @Previewable @State var compression = true
    @Previewable @State var forwarding = false

    return VStack(alignment: .leading, spacing: Spacing.snug) {
        Toggle("Compression", isOn: $compression)
        Toggle("ForwardAgent", isOn: $forwarding)
    }
    .toggleStyle(.panel)
    .padding(Spacing.loose)
    .frame(width: 320)
}
