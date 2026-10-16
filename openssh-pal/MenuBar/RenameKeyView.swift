import SwiftUI

/// The rename entry, presented in place of the selected key's actions.
///
/// Named for what it is rather than for a sheet: the panel has no key window, so a modal
/// attached to it is unreliable, and the rename stays inside the surface.
///
/// The field's validation message occupies its slot whether or not there is a message —
/// `LabeledField` reserves it — so a rejected name does not change this surface's height.
struct RenameKeyView: View {

    @Bindable var model: SSHKeyListModel

    let pair: SSHKeyPair

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            LabeledField(
                label: "New name",
                text: $model.renameProposal,
                validation: model.renameValidation,
                prompt: pair.displayName
            )

            HStack(spacing: Spacing.snug) {
                Button("Cancel") { model.cancelRename() }
                    .accessibilityLabel("Cancel renaming \(pair.displayName)")

                // Gated through the design system's confirming style, which is also what
                // carries the warning: the app does not update what points at a key, so the
                // user has to be told before anything moves. The destructive role is what
                // engages that gate — and a rename that breaks an `IdentityFile` reference
                // has earned the appearance.
                Button("Rename", role: .destructive) {
                    Task { await model.confirmRename() }
                }
                .disabled(!model.canConfirmRename)
                .buttonStyle(
                    .confirming(
                        title: model.renameWarningTitle ?? "",
                        message: model.renameWarningMessage ?? ""
                    )
                )
                .accessibilityLabel("Rename \(pair.displayName)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
