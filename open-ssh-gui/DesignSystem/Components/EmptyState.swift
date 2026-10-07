import SwiftUI

/// Shown in place of a collection that has no items.
///
/// An empty collection is ordinary content, not a failure, so this renders in the secondary text
/// role rather than as a warning.
struct EmptyState: View {

    let content: EmptyStateContent

    var body: some View {
        VStack(spacing: Spacing.snug) {
            if let symbolName = content.symbolName {
                Image(systemName: symbolName)
                    .font(.title2)
                    .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))
                    .accessibilityHidden(true)
            }

            Text(content.message)
                .font(Typography.fieldLabel)
                .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let action = content.action {
                // A plain `Button`, so it inherits the project's button appearance rather than
                // inventing one for empty states.
                Button(action.title) { action.perform() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.loose)
    }
}

#Preview("Empty state shapes") {
    VStack(spacing: Spacing.loose) {
        EmptyState(content: EmptyStateContent(message: "No hosts in this configuration"))
        EmptyState(content: EmptyStateContent(message: "No key pairs found", symbolName: "key"))
        EmptyState(
            content: EmptyStateContent(
                message: "No hosts yet",
                symbolName: "server.rack",
                action: EmptyStateContent.Action(title: "Add a host") {}
            )
        )
    }
    .padding(Spacing.loose)
    .frame(width: 320)
}
