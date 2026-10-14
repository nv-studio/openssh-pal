import SwiftUI

/// One key the host form offers.
///
/// A list row rather than a menu item, because macOS draws menu item images as monochrome
/// templates and the shared-key warning has to be the design system's warning colour.
struct HostKeyChoiceRowView: View {

    let option: HostKeyChoiceOption

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.snug) {
            Image(systemName: option.symbolName)
                .foregroundStyle(ColorRoleAppearance.style(for: option.symbolColor))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(option.title)
                    .font(Typography.control)
                    .foregroundStyle(ColorRoleAppearance.style(for: option.isAvailable ? .primaryText : .secondaryText))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let line = option.sharingText ?? option.detail {
                    Text(line)
                        .font(Typography.fieldMessage)
                        .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.hairline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.accessibilityLabel)
        // A pair whose private key is gone cannot be chosen; the model would ignore it anyway.
        .selectionDisabled(!option.isAvailable)
    }
}

#if DEBUG
#Preview("Available, shared and unavailable") {
    VStack(alignment: .leading, spacing: Spacing.snug) {
        HostKeyChoiceRowView(option: HostKeyChoiceOption(choice: .none, title: "No key", detail: "ssh uses its default identities", isAvailable: true, sharingHosts: []))
        HostKeyChoiceRowView(option: HostKeyChoiceOption(choice: .none, title: "id_work", detail: "ED25519 256", isAvailable: true, sharingHosts: ["bastion", "web"]))
        HostKeyChoiceRowView(option: HostKeyChoiceOption(choice: .none, title: "orphan", detail: "The private key is missing", isAvailable: false, sharingHosts: []))
    }
    .padding(PanelMetrics.contentInset)
    .frame(width: PanelMetrics.width)
}
#endif
