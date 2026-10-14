import SwiftUI

/// One host entry, as a row in the list.
///
/// Compact for the same reason `SSHKeyRowView` is: the detail a selected host needs is shown
/// below the list, not inside every row. Every word and symbol comes from the presentation, and
/// every appearance from the design system.
struct HostRowView: View {

    let presentation: HostEntryPresentation

    /// Whether a change is running on this entry, so the row can say so.
    let isOperating: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.snug) {
            Image(systemName: isOperating ? StatusRole.inProgress.symbolName : presentation.symbolName)
                .foregroundStyle(ColorRoleAppearance.style(for: isOperating ? .secondaryText : presentation.symbolColor))
                // The label below says everything the symbol does, warning included.
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                HStack(spacing: Spacing.tight) {
                    Text(presentation.title)
                        .font(Typography.control)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let marker = presentation.patternMarker {
                        Text(marker)
                            .font(Typography.fieldMessage)
                            .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))
                    }
                }

                Text(presentation.detailLine)
                    .font(Typography.fieldMessage)
                    .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.hairline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isOperating ? "\(presentation.accessibilityLabel). Working…" : presentation.accessibilityLabel)
    }
}

#if DEBUG
#Preview("Concrete, pattern, shared and in progress") {
    let file = URL(filePath: "/preview/keys/config")
    let parsed = SSHConfigParser().parse(
        Data("Host web\n    HostName 10.0.0.5\n    User deploy\nHost *.corp\n    User c\nHost bastion\n".utf8),
        at: file,
        inclusionChain: [],
        writability: .writable
    )
    let work = SSHKeyName.discovered("id_work")!

    return VStack(alignment: .leading, spacing: Spacing.snug) {
        HostRowView(
            presentation: HostEntryPresentation(entry: parsed.entries[0], associations: [.listed(work)], sharingHosts: ["bastion"], file: "config", isDeclaredInConfig: true),
            isOperating: false
        )
        HostRowView(
            presentation: HostEntryPresentation(entry: parsed.entries[1], associations: [], sharingHosts: [], file: "config.d/corp", isDeclaredInConfig: false),
            isOperating: false
        )
        HostRowView(
            presentation: HostEntryPresentation(entry: parsed.entries[2], associations: [.unresolved(raw: "~/keys/%h", .connectionToken("%h"))], sharingHosts: [], file: "config", isDeclaredInConfig: true),
            isOperating: true
        )
    }
    .padding(PanelMetrics.contentInset)
    .frame(width: PanelMetrics.width)
}
#endif
