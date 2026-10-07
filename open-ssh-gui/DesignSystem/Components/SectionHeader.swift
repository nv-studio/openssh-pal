import SwiftUI

/// Heads a group of related content inside the panel.
struct SectionHeader: View {

    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Typography.sectionHeader)
            .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))
            .frame(maxWidth: .infinity, alignment: .leading)
            // A screen reader user navigates by heading; without this the panel is one flat run
            // of text.
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Section header") {
    VStack(alignment: .leading, spacing: Spacing.snug) {
        SectionHeader(title: "Hosts")
        Text("content below the header").font(Typography.control)
    }
    .padding(Spacing.loose)
    .frame(width: 320)
}
