import SwiftUI

/// How an icon-and-title label reads in the panel.
struct PanelLabelStyle: LabelStyle {

    enum Emphasis: Sendable {
        case primary
        case secondary
    }

    let emphasis: Emphasis

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.tight) {
            configuration.icon
            configuration.title
        }
        .font(emphasis == .primary ? Typography.control : Typography.fieldLabel)
        .foregroundStyle(
            ColorRoleAppearance.style(for: emphasis == .primary ? .primaryText : .secondaryText)
        )
        // The panel has a fixed width, so long text wraps to a bound and then truncates rather
        // than widening the window.
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Icon and title are one thing to a screen reader, not two.
        .accessibilityElement(children: .combine)
    }
}

extension LabelStyle where Self == PanelLabelStyle {
    static var panel: PanelLabelStyle { PanelLabelStyle(emphasis: .primary) }
    static var panelSecondary: PanelLabelStyle { PanelLabelStyle(emphasis: .secondary) }
}

#Preview("Label emphases and truncation") {
    VStack(alignment: .leading, spacing: Spacing.regular) {
        Label("Reachable", systemImage: StatusRole.success.symbolName)
            .labelStyle(.panel)
        Label("Supporting detail", systemImage: "info.circle")
            .labelStyle(.panelSecondary)
        Label(
            "A label long enough to need two lines and then truncate instead of widening the panel",
            systemImage: "text.alignleft"
        )
        .labelStyle(.panel)
    }
    .padding(Spacing.loose)
    .frame(width: 320)
}
