import SwiftUI

/// A row of mutually exclusive sections at the top of a panel.
///
/// A segmented picker rather than a `TabView`: `TabView`'s behaviour inside a content-sized
/// `NSPanel` is undocumented and is the change most likely to bring layout recursion back,
/// while a segmented control is one fixed height. It also shows the selection by shape and
/// contrast — the selected segment is raised — not by tint alone, and exposes each segment's
/// name and selected state to VoiceOver natively.
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
        Picker(label, selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(title(option)).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(label)
        .frame(maxWidth: .infinity)
        // Exact, for the reason every panel region is: a height that settled after the first
        // layout pass is what AppKit reports as layout recursion.
        .frame(height: PanelMetrics.tabBarHeight)
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
