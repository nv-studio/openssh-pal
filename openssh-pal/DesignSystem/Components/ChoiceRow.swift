import SwiftUI

/// A row for choosing one of a fixed set of options.
///
/// Built on the native picker because `PickerStyle` declares no public requirement and cannot be
/// implemented. Generic over the option type and **enumerates nothing itself**: the caller supplies
/// both the options and how to title them, so no OpenSSH keyword or value appears in this layer.
struct ChoiceRow<Option: Hashable>: View {

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
        LabeledContent(label) {
            Picker(label, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(title(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel(label)
        }
    }
}

#Preview("Renders exactly the options the caller supplies") {
    @Previewable @State var selection = "ed25519"

    return VStack(spacing: Spacing.snug) {
        ChoiceRow(
            label: "Key type",
            options: ["ed25519", "rsa", "ecdsa"],
            selection: $selection
        ) { $0 }
    }
    .labeledContentStyle(.panel)
    .padding(Spacing.loose)
    .frame(width: 320)
}
