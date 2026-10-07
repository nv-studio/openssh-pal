import SwiftUI

/// How a name-and-value row reads in the panel.
struct PanelRowStyle: LabeledContentStyle {

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.regular) {
            configuration.label
                .font(Typography.fieldLabel)
                .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))

            Spacer(minLength: Spacing.tight)

            configuration.content
                .font(Typography.control)
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension LabeledContentStyle where Self == PanelRowStyle {
    static var panel: PanelRowStyle { PanelRowStyle() }
}

#Preview("Name and value rows") {
    VStack(spacing: Spacing.snug) {
        LabeledContent("HostName", value: "bastion.example.com")
        LabeledContent("Port", value: "22")
        LabeledContent("IdentityFile", value: "~/.ssh/id_ed25519")
    }
    .labeledContentStyle(.panel)
    .padding(Spacing.loose)
    .frame(width: 320)
}
