import SwiftUI

/// A passphrase entry that is redacted until the user asks to see it.
///
/// The design system's secret field *renders* a value it is handed; it does not collect one,
/// and it is not an editable control. So entry is composed here from the native secure field
/// plus the design system's own chrome — which keeps every appearance decision in that layer
/// while this spec supplies the reveal policy, exactly as the seam was drawn.
///
/// The reveal flag belongs to the caller. This view reports a request and never decides on
/// its own authority, which is the same contract the design system's secret field states.
struct PassphraseField: View {

    let label: String

    @Binding var text: String

    /// How much of the value the caller has authorised showing. A redacted presentation
    /// carries no value, which is why the decision is read from it rather than from a flag.
    let presentation: SecretPresentation

    let validation: FieldValidation

    /// What the caller wants said about an empty or mismatched entry, shown in the slot
    /// `LabeledField` would use for a validation message.
    let note: String?

    let onRevealRequested: () -> Void
    let onHideRequested: () -> Void

    /// The note's reserved height, so a note appearing never changes this field's height —
    /// the panel is a fixed size and a region that grew mid-layout is what produced
    /// `_NSDetectedLayoutRecursion` once already.
    @ScaledMetric(relativeTo: .caption) private var noteHeight = PanelMetrics.fieldMessageHeight

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(label)
                .font(Typography.fieldLabel)
                .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))

            HStack(spacing: Spacing.snug) {
                field

                Button(presentation.isRevealed ? "Hide" : "Reveal") {
                    if presentation.isRevealed { onHideRequested() } else { onRevealRequested() }
                }
                .accessibilityLabel(presentation.isRevealed ? "Hide \(label)" : "Reveal \(label)")
            }

            Text(message ?? " ")
                .font(Typography.fieldMessage)
                .foregroundStyle(ColorRoleAppearance.style(for: validation.isValid ? .secondaryText : .failure))
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(message == nil ? 0 : 1)
                .frame(height: noteHeight, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(message == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A secure field while redacted and a plain one while revealed.
    ///
    /// Two controls rather than one with a toggle, because a secure field cannot be made to
    /// show its contents — and showing them is the whole of what a reveal means.
    @ViewBuilder private var field: some View {
        if presentation.isRevealed {
            TextField(label, text: $text)
                .labelsHidden()
                .fieldChrome(validation: validation)
                .accessibilityLabel(label)
        } else {
            SecureField(label, text: $text)
                .labelsHidden()
                .fieldChrome(validation: validation)
                // Describes the field, never its contents.
                .accessibilityLabel("\(label), hidden")
        }
    }

    private var message: String? {
        validation.message ?? note
    }
}

#Preview("Redacted, revealed, mismatched and annotated") {
    @Previewable @State var passphrase = "hunter2"

    return VStack(alignment: .leading, spacing: Spacing.regular) {
        PassphraseField(
            label: "Passphrase",
            text: $passphrase,
            presentation: .redacted(placeholderLength: passphrase.count),
            validation: .valid,
            note: nil,
            onRevealRequested: {},
            onHideRequested: {}
        )
        PassphraseField(
            label: "Passphrase",
            text: $passphrase,
            presentation: .revealed(passphrase),
            validation: .valid,
            note: "With no passphrase, the private key is stored unencrypted.",
            onRevealRequested: {},
            onHideRequested: {}
        )
        PassphraseField(
            label: "Confirm passphrase",
            text: $passphrase,
            presentation: .redacted(placeholderLength: passphrase.count),
            validation: .invalid("The two passphrases do not match."),
            note: nil,
            onRevealRequested: {},
            onHideRequested: {}
        )
    }
    .buttonStyle(.panelPlain)
    .padding(Spacing.loose)
    .frame(width: PanelMetrics.width)
}
