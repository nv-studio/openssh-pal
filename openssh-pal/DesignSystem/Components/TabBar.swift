import SwiftUI

/// A row of mutually exclusive sections at the top of a panel.
///
/// A row of plain buttons rather than a `TabView`: `TabView`'s behaviour inside a
/// content-sized `NSPanel` is undocumented and is the change most likely to bring layout
/// recursion back, while this row is one fixed height. The tabs have no background and sit at
/// the leading edge; the selected one is shown by brighter text *and* an underline, so the
/// selection is carried by shape as well as contrast, and VoiceOver hears it as the button's
/// selected trait.
///
/// Generic over the option type and **enumerates nothing itself**: the caller supplies the
/// options and their titles, so no OpenSSH concept appears in this layer.
struct TabBar<Option: Hashable>: View {

    /// What the sections are, for a screen reader. Not drawn.
    let label: String

    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    init(
        label: String,
        options: [Option],
        selection: Binding<Option>,
        title: @escaping (Option) -> String
    ) {
        self.label = label
        self.options = options
        self._selection = selection
        self.title = title
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.loose) {
            ForEach(options, id: \.self) { option in
                tab(for: option)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        // Exact, for the reason every panel region is: a height that settled after the first
        // layout pass is what AppKit reports as layout recursion.
        .frame(height: PanelMetrics.tabBarHeight, alignment: .bottomLeading)
    }

    private func tab(for option: Option) -> some View {
        let isSelected = option == selection

        // `.plain` rather than the scene's panel style, which would draw button chrome behind
        // every tab.
        return Button { selection = option } label: {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(title(option))
                    .font(Typography.tab)
                    .lineLimit(1)

                // Present on every tab and only drawn on the selected one, so selecting a tab
                // never moves its title. Filled with the same role as the selected title, an
                // opaque colour (see `ColorRoleAppearance`), so it is exactly as bright as the
                // title above it.
                Rectangle()
                    .fill(ColorRoleAppearance.style(for: .selectedTab))
                    .frame(height: PanelMetrics.tabUnderlineHeight)
                    .opacity(isSelected ? 1 : 0)
            }
            .foregroundStyle(ColorRoleAppearance.style(for: isSelected ? .selectedTab : .secondaryText))
            .fixedSize()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Set here because `.plain` bypasses `PanelButtonStyle`, which is where every other
        // button gets its cursor.
        .pressablePointer()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Three sections, each selected in turn") {
    @Previewable @State var selection = "Second"

    return VStack(spacing: Spacing.loose) {
        TabBar(label: "Sections", options: ["First", "Second", "Third"], selection: $selection) { $0 }
        TabBar(label: "Sections", options: ["First", "Second", "Third"], selection: .constant("First")) { $0 }
    }
    .padding(PanelMetrics.contentInset)
    .frame(width: PanelMetrics.width)
}
