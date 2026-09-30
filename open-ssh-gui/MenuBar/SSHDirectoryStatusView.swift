import SwiftUI

/// The contents of the menu bar panel.
///
/// Holds no logic and reaches nothing: every string it shows comes from
/// `SSHDirectoryStatus`, and the only work it triggers is `refresh()` when the panel opens.
struct SSHDirectoryStatusView: View {
    let model: SSHDirectoryStatusModel

    /// Height reserved for the path and indicator rows together.
    ///
    /// `menuBarExtraStyle(.window)` hosts this view in a panel that sizes itself to its
    /// content, and `refresh()` settles `.resolving` into a terminal state while that panel
    /// is still being laid out. Letting the content change height at that moment makes AppKit
    /// re-enter layout, which it reports as `_NSDetectedLayoutRecursion`. Reserving the
    /// worst-case height up front keeps the panel one fixed size, so the state change
    /// repaints without resizing anything.
    ///
    /// Both rows are bounded to two lines, so this covers every state. `@ScaledMetric` keeps
    /// it correct when the user's text size differs from the default.
    @ScaledMetric(relativeTo: .body) private var reservedStatusHeight: CGFloat = 70

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SSH directory")
                .font(.headline)

            // Both rows are always present, so settling out of `.resolving` swaps text rather
            // than adding or removing views.
            VStack(alignment: .leading, spacing: 6) {
                path
                indicator
            }
            .frame(minHeight: reservedStatusHeight, alignment: .topLeading)

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

    /// The resolved directory, or the path an override was rejected for.
    private var path: some View {
        Text(model.status.displayPath ?? "—")
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(2)
            .truncationMode(.middle)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Reachability, or the reason in its place when the directory cannot be reached.
    private var indicator: some View {
        let status = model.status

        return Group {
            if let reason = status.failureReason {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if status.isReachable {
                Label("Reachable", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Resolving…", systemImage: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
