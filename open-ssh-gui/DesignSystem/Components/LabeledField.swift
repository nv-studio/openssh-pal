import SwiftUI

/// A label, an editable field and a validation message as one unit.
///
/// Owns the layout and the label-to-field association, and nothing else: the text is the caller's
/// binding and the verdict is the caller's value. This component never decides whether the
/// contents are acceptable.
struct LabeledField: View {

    let label: String
    @Binding var text: String
    let validation: FieldValidation
    let prompt: String?
    let focus: FocusState<Bool>.Binding?

    /// The validation message's reserved height.
    ///
    /// The slot is occupied whether or not there is a message, so showing one never changes this
    /// component's height. The panel sizes itself to its content, and a height change while AppKit
    /// is laying it out is what produced `_NSDetectedLayoutRecursion` once already — see the
    /// reserved height this project already carries in its status view.
    @ScaledMetric(relativeTo: .caption) private var messageHeight: CGFloat = 14

    init(
        label: String,
        text: Binding<String>,
        validation: FieldValidation = .valid,
        prompt: String? = nil,
        focus: FocusState<Bool>.Binding? = nil
    ) {
        self.label = label
        self._text = text
        self.validation = validation
        self.prompt = prompt
        self.focus = focus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(label)
                .font(Typography.fieldLabel)
                .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))

            field

            message
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Focus is the caller's to drive when it needs to — jumping to the first invalid field, for
    /// instance — so it arrives as a binding rather than being owned here.
    @ViewBuilder private var field: some View {
        if let focus {
            textField.focused(focus)
        } else {
            textField
        }
    }

    private var textField: some View {
        TextField(label, text: $text, prompt: prompt.map(Text.init))
            .labelsHidden()
            .fieldChrome(validation: validation)
            // Ties the visible label to the field for a screen reader, which `labelsHidden`
            // would otherwise sever.
            .accessibilityLabel(label)
    }

    private var message: some View {
        Text(validation.message ?? " ")
            .font(Typography.fieldMessage)
            .foregroundStyle(ColorRoleAppearance.style(for: .failure))
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(validation.isValid ? 0 : 1)
            .frame(height: messageHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(validation.isValid)
    }
}

#Preview("Valid, invalid and long message all occupy the same height") {
    @Previewable @State var valid = "bastion.example.com"
    @Previewable @State var invalid = ""
    @Previewable @State var long = "x"

    return VStack(alignment: .leading, spacing: Spacing.regular) {
        LabeledField(label: "HostName", text: $valid)
        LabeledField(label: "HostName", text: $invalid, validation: .invalid("HostName is required"))
        LabeledField(
            label: "IdentityFile",
            text: $long,
            validation: .invalid("A message long enough that it has to truncate rather than grow the panel")
        )
    }
    .padding(Spacing.loose)
    .frame(width: 320)
}
