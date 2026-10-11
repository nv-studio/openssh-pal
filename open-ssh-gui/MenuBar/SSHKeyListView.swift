import SwiftUI

/// The key list surface: which directory the app is pointed at, and the pairs inside it.
///
/// Holds no logic and reaches nothing. Every value comes from the two injected models, and
/// every appearance decision from the design system — there is not a font, spacing, radius or
/// colour literal anywhere below.
///
/// The surface is an exact height, so switching to the create form cannot change the panel's
/// size.
struct SSHKeyListView: View {

    @Bindable var model: SSHKeyListModel

    /// Kept alongside the list because the user needs to know *which* directory these keys
    /// are in, especially under a launch override.
    let status: SSHDirectoryStatusModel

    /// Asks the panel to show the create form. The route is the panel's to own.
    let onCreate: () -> Void

    @State private var selection: SSHKeyName?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            directorySection

            Divider()

            keysSection

            Spacer(minLength: 0)
        }
        .frame(width: PanelMetrics.width, height: PanelMetrics.surfaceHeight, alignment: .top)
        .task { await model.refresh() }
    }

    // MARK: - The directory

    private var directorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            SectionHeader(title: "SSH directory")
            CodeText(text: status.status.displayPath ?? "—", lineLimit: 1)
            StatusIndicator(role: status.status.statusRole, message: status.status.statusMessage)
        }
    }

    // MARK: - The keys

    private var keysSection: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            SectionHeader(title: "Key pairs")

            // The region is one height whichever of the three things it holds, so neither an
            // empty directory nor an unreadable one moves what is below it.
            listRegion
                .frame(height: PanelMetrics.keyListHeight, alignment: .top)

            detailRegion

            actionsRegion
        }
    }

    @ViewBuilder private var listRegion: some View {
        if let reason = model.state.failureReason {
            // An unreadable directory presents its reason. It is deliberately *not* the empty
            // state: telling the user they have no keys when the app could not look would be
            // worse than saying nothing.
            StatusIndicator(role: .failure, message: reason)
        } else {
            BoundedList(
                elements: model.state.pairs,
                selection: $selection,
                emptyState: EmptyStateContent(message: "No key pairs found", symbolName: "key"),
                maximumHeight: PanelMetrics.keyListHeight
            ) { pair in
                SSHKeyRowView(pair: pair, isOperating: model.operation.name == pair.id)
            }
        }
    }

    /// The selected key's attributes.
    ///
    /// The fingerprint lives here rather than in every row for one reason: it is 50 characters
    /// of base64, and a 320-point row cannot show it without eliding the part that identifies
    /// it. Here it has the width to be read — and compared against `ssh-keygen -l` — character
    /// by character.
    ///
    /// The slot is reserved whether or not anything is selected, so selecting a key does not
    /// move the controls beneath it.
    private var detailRegion: some View {
        Group {
            if let pair = selectedPair {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    StatusIndicator(
                        role: model.operation.name == pair.id ? .inProgress : pair.statusRole,
                        message: model.operation.name == pair.id ? "Working…" : pair.statusMessage
                    )

                    LabeledContent("Type", value: pair.typeText)
                    LabeledContent("Comment", value: pair.commentText)

                    CodeText(text: pair.fingerprintText, lineLimit: 1)
                }
            } else if !model.state.pairs.isEmpty {
                StatusIndicator(role: .inProgress, message: "Select a key to copy, rename or delete it.")
            }
        }
        .frame(height: PanelMetrics.keyDetailHeight, alignment: .topLeading)
    }

    @ViewBuilder private var actionsRegion: some View {
        if let pair = model.renamingPair {
            RenameKeyView(model: model, pair: pair)
        } else {
            HStack(spacing: Spacing.snug) {
                if let pair = selectedPair {
                    Button("Copy") { Task { await model.copyPublicKey(of: pair) } }
                        .accessibilityLabel("Copy \(pair.displayName) public key")

                    Button("Rename") { model.beginRename(of: pair) }
                        .accessibilityLabel("Rename \(pair.displayName)")

                    Button("Delete", role: .destructive) {
                        Task { await model.delete(pair) }
                    }
                    .buttonStyle(
                        .confirming(
                            title: model.deletionTitle(for: pair),
                            message: model.deletionMessage(for: pair)
                        )
                    )
                    .accessibilityLabel("Delete \(pair.displayName)")
                }

                Spacer(minLength: 0)

                Button("New key") { onCreate() }
                    // Offered only once a directory has resolved: there is nowhere to write
                    // a key until then, and there is deliberately no fallback.
                    .disabled(model.resolvedDirectory == nil)
                    .accessibilityLabel("Create a new key pair")
            }
            .disabled(model.operation.isInFlight)
        }
    }

    private var selectedPair: SSHKeyPair? {
        model.state.pairs.first { $0.id == selection }
    }
}
