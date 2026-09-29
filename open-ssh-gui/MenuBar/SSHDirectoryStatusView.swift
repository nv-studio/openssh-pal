import SwiftUI

/// The contents of the menu bar panel.
///
/// Holds no logic and reaches nothing: every string it shows comes from
/// `SSHDirectoryStatus`, and the only work it triggers is `refresh()` when the panel opens.
struct SSHDirectoryStatusView: View {
    let model: SSHDirectoryStatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SSH directory")
                .font(.headline)

            directory

            Divider()

            // An agent-mode app has no Dock icon and no menu bar menu of its own, so this is
            // the user's only way to quit.
            Button("Quit open-ssh-gui") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .task { await model.refresh() }
    }

    @ViewBuilder
    private var directory: some View {
        let status = model.status

        if let path = status.displayPath {
            Text(path)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)

            if let reason = status.failureReason {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else if status.isReachable {
                Label("Reachable", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }
        } else {
            Label("Resolving…", systemImage: "ellipsis.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}
