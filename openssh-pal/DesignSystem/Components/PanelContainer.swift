import SwiftUI

/// A tinted, rounded group inside the panel: what sets the tab bar and the selected tab's
/// surface apart from the panel and from each other.
///
/// Fills the width it is offered and pads its content by `insets`, so a surface inside it is
/// laid out at the panel's width less `edgeInset` and the container's padding on each side —
/// which is what `PanelMetrics.contentWidth` is.
struct PanelContainer<Content: View>: View {

    let insets: EdgeInsets
    let content: Content

    init(insets: EdgeInsets, @ViewBuilder content: () -> Content) {
        self.insets = insets
        self.content = content()
    }

    var body: some View {
        content
            .padding(insets)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                ColorRoleAppearance.style(for: .containerBackground),
                in: .rect(cornerRadius: Radius.panel)
            )
    }
}

#Preview("Two containers separated by a gap") {
    let padding = PanelMetrics.containerPadding

    return VStack(spacing: Spacing.regular) {
        PanelContainer(insets: EdgeInsets(top: Spacing.snug, leading: padding, bottom: Spacing.snug, trailing: padding)) {
            Text("Tab bar")
        }
        .frame(height: PanelMetrics.tabContainerHeight)

        PanelContainer(insets: EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)) {
            Text("Surface")
        }
        .frame(height: 120)
    }
    .padding(PanelMetrics.edgeInset)
    .frame(width: PanelMetrics.width)
}
