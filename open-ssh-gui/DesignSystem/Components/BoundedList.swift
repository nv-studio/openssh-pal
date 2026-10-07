import SwiftUI

/// A collection rendered at a bounded height, with its own empty state.
///
/// The height is explicit and never derived from content: the menu bar panel sizes itself to what
/// it contains, so a list that grew with its data would resize the window as the data arrived.
struct BoundedList<Element: Identifiable, Row: View>: View {

    let elements: [Element]
    @Binding var selection: Element.ID?
    let emptyState: EmptyStateContent
    let row: (Element) -> Row

    /// Scales with the user's text size, so the bound holds about the same number of rows
    /// whatever size they read at.
    @ScaledMetric(relativeTo: .body) private var maximumHeight: CGFloat = 140

    init(
        elements: [Element],
        selection: Binding<Element.ID?>,
        emptyState: EmptyStateContent,
        @ViewBuilder row: @escaping (Element) -> Row
    ) {
        self.elements = elements
        self._selection = selection
        self.emptyState = emptyState
        self.row = row
    }

    var body: some View {
        if elements.isEmpty {
            // An empty collection gets the empty state, not an empty rows area with a border
            // around nothing.
            EmptyState(content: emptyState)
        } else {
            List(elements, selection: $selection) { element in
                row(element)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(height: maximumHeight)
        }
    }
}

#Preview("Empty, one row, and more rows than the bound") {
    @Previewable @State var selection: Int?

    struct Host: Identifiable {
        let id: Int
        let name: String
    }

    let many = (1...12).map { Host(id: $0, name: "host-\($0).example.com") }

    return VStack(alignment: .leading, spacing: Spacing.loose) {
        BoundedList(
            elements: [Host](),
            selection: $selection,
            emptyState: EmptyStateContent(message: "No hosts configured", symbolName: "server.rack")
        ) { Text($0.name) }

        BoundedList(
            elements: [Host(id: 0, name: "bastion.example.com")],
            selection: $selection,
            emptyState: EmptyStateContent(message: "No hosts configured")
        ) { Text($0.name) }

        BoundedList(
            elements: many,
            selection: $selection,
            emptyState: EmptyStateContent(message: "No hosts configured")
        ) { Text($0.name) }
    }
    .padding(Spacing.loose)
    .frame(width: 320)
}
