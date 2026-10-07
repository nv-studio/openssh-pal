import SwiftUI

/// **TEMPORARY — the next feature spec deletes this directory.**
///
/// Demonstrates every design system component at the panel's real width, which is the point: a
/// gallery in a roomy window would hide exactly the truncation and wrapping problems a 320pt panel
/// creates. Removing it is deleting `Showcase/` and the one line in `OpenSSHGUIApp` that presents
/// it — no design system file refers to anything in here.
struct ShowcasePanel: View {

    /// The scrolling region's height is explicit, never derived from content.
    ///
    /// `menuBarExtraStyle(.window)` hosts this in a panel that sizes itself to what it contains, so
    /// a region that grew as its content settled would resize the panel mid-layout — which AppKit
    /// reports as `_NSDetectedLayoutRecursion`. Scaled, so the bound holds at any text size.
    @ScaledMetric(relativeTo: .body) private var scrollHeight = PanelMetrics.maximumScrollHeight

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            Text("Design system")
                .font(Typography.panelTitle)

            ScrollView {
                ShowcaseSections()
                    .padding(.trailing, Spacing.snug)
            }
            .frame(height: scrollHeight)

            Divider()

            // Outside the scrolling region on purpose: an agent-mode app has no Dock icon, so this
            // is the only way out and it must never be scrolled off.
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(Spacing.loose)
        .frame(width: PanelMetrics.width, alignment: .leading)
    }
}

#Preview("The whole showcase panel") {
    ShowcasePanel()
        .buttonStyle(.panelPlain)
        .labelStyle(.panel)
        .labeledContentStyle(.panel)
        .toggleStyle(.panel)
}
