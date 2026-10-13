import SwiftUI

/// Reports a state as an icon, a message and a tint.
///
/// Holds no opinion about what the state means: the caller supplies both the role and the words.
struct StatusIndicator: View {

    let role: StatusRole
    let message: String

    var body: some View {
        Label {
            Text(message)
        } icon: {
            // The icon's own tint, applied inside, wins over the label style's outer colour.
            Image(systemName: role.symbolName)
                .foregroundStyle(ColorRoleAppearance.style(for: role.colorRole))
        }
        .font(Typography.statusMessage)
        // Reserved for the same reason as `CodeText`: a status settling from one line to two must
        // not resize the panel around it.
        .lineLimit(2, reservesSpace: true)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Every status, distinguishable by icon as well as tint") {
    VStack(alignment: .leading, spacing: Spacing.snug) {
        StatusIndicator(role: .success, message: "Reachable")
        StatusIndicator(role: .warning, message: "Permissions are more open than ssh accepts")
        StatusIndicator(role: .failure, message: "Permission denied")
        StatusIndicator(role: .inProgress, message: "Resolving…")
    }
    .padding(Spacing.loose)
    .frame(width: 320)
}
