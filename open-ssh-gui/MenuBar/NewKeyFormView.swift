import SwiftUI

/// The create form surface.
///
/// Holds no logic: every field binds to the model, every verdict is read from it, and every
/// appearance decision comes from the design system. The fields scroll inside a bounded
/// region so that the surface — and therefore the panel — is one height whatever is on show.
struct NewKeyFormView: View {

    @Bindable var model: NewKeyFormModel

    /// Asks the panel to go back to the list. The route is the panel's to own.
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.loose) {
            SectionHeader(title: "New key pair")

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.regular) {
                    nameAndType
                    comment
                    passphrases
                }
                // Keeps the scroll indicator off the field chrome, and leaves the last field
                // clear of the footer when the region is scrolled to its end.
                .padding(.trailing, Spacing.snug)
                .padding(.bottom, Spacing.snug)
            }

            footer
        }
        .frame(width: PanelMetrics.contentWidth, height: PanelMetrics.surfaceHeight, alignment: .top)
    }

    // MARK: - Fields

    private var nameAndType: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            LabeledField(
                label: "File name",
                text: $model.name,
                validation: model.nameValidation,
                prompt: "id_ed25519"
            )

            ChoiceRow(
                label: "Type",
                options: model.families,
                selection: Binding(get: { model.type.family }, set: { model.select($0) })
            ) { $0.displayName }

            // Only the selected type's parameter is offered. There is no branch for "both",
            // because the type cannot hold both.
            if let length = model.rsaLength {
                ChoiceRow(
                    label: "Size",
                    options: model.rsaLengths,
                    selection: Binding(get: { length }, set: { model.select($0) })
                ) { $0.displayName }
            }

            if let curve = model.curve {
                ChoiceRow(
                    label: "Curve",
                    options: model.curves,
                    selection: Binding(get: { curve }, set: { model.select($0) })
                ) { $0.displayName }
            }
        }
    }

    private var comment: some View {
        LabeledField(label: "Comment", text: $model.comment, prompt: "user@host")
    }

    private var passphrases: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            PassphraseField(
                label: "Passphrase",
                text: $model.passphraseText,
                presentation: model.passphrasePresentation,
                validation: .valid,
                note: model.passphraseNotice,
                onRevealRequested: { model.revealPassphrase() },
                onHideRequested: { model.hidePassphrase() }
            )

            PassphraseField(
                label: "Confirm passphrase",
                text: $model.confirmationText,
                presentation: model.passphrasePresentation,
                validation: model.passphraseValidation,
                note: nil,
                onRevealRequested: { model.revealPassphrase() },
                onHideRequested: { model.hidePassphrase() }
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            if model.isGenerating {
                StatusIndicator(role: .inProgress, message: "Generating…")
            } else if let reason = model.failureReason {
                StatusIndicator(role: .failure, message: reason)
            }

            HStack(spacing: Spacing.snug) {
                Button("Cancel") {
                    model.cancel()
                    onCancel()
                }
                .accessibilityLabel("Cancel and return to the key list")

                Spacer(minLength: 0)

                Button("Generate") { model.submit() }
                    .disabled(!model.canGenerate)
                    .accessibilityLabel("Generate the key pair")
            }
        }
    }
}
