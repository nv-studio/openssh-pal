import SwiftUI

/// Which directory the app is pointed at, and whether it can be read.
///
/// A section rather than the panel's whole content: it was the panel until the key list
/// arrived, and `PanelView` now owns the gutter and the Quit control. Reduced rather than
/// abandoned, so there is one view that decides how a directory is laid out instead of a live
/// copy inside the key list and an orphan here that could drift apart.
///
/// Holds no logic and reaches nothing: every string comes from `SSHDirectoryStatus`. It
/// declares no font, radius or colour of its own, and no spacing beyond the gaps between its
/// own three rows — all of it from the design system, which is what makes a change to the
/// project's appearance one edit rather than a search through views.
///
/// Drives no refresh. The key list's own refresh settles this status first, and a second
/// `.task` here would re-read the directory on every open for nothing.
struct SSHDirectoryStatusView: View {

    let model: SSHDirectoryStatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            SectionHeader(title: "SSH directory")
            CodeText(text: model.status.displayPath ?? "—", lineLimit: 1)
            StatusIndicator(role: model.status.statusRole, message: model.status.statusMessage)
        }
        // Fills the surface so the path and the indicator start at the same edge as everything
        // below them, instead of being centred on their own intrinsic width.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
