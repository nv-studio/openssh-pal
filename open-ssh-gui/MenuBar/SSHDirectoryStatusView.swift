import SwiftUI

/// The contents of the menu bar panel.
///
/// Holds no logic and reaches nothing: every string it shows comes from `SSHDirectoryStatus`, and
/// the only work it triggers is `refresh()` when the panel opens.
///
/// It also declares no font, spacing, radius or colour of its own — all of that comes from the
/// design system, which is what makes a change to the project's appearance one edit rather than a
/// search through views. The reserved height this view used to carry is gone because `CodeText`
/// and `StatusIndicator` now reserve their own, so the panel is a fixed size without this view
/// having to know why.
struct SSHDirectoryStatusView: View {
    let model: SSHDirectoryStatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            SectionHeader(title: "SSH directory")

            VStack(alignment: .leading, spacing: Spacing.snug) {
                CodeText(text: model.status.displayPath ?? "—")
                StatusIndicator(role: model.status.statusRole, message: model.status.statusMessage)
            }

            Divider()

            // An agent-mode app has no Dock icon and no menu bar menu of its own, so this is
            // the user's only way to quit. The destructive role is how the design system is told
            // to colour it as a departure, rather than tinting it at this call site.
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(Spacing.loose)
        .frame(width: PanelMetrics.width, alignment: .leading)
        .task { await model.refresh() }
    }
}
