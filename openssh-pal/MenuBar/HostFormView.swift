import SwiftUI

/// The create and edit form for one host, shown in the Hosts tab in place of the list.
///
/// Holds no logic: fields bind to the draft, every verdict and every choice is read from the
/// model, and every appearance comes from the design system. The fields scroll inside a bounded
/// region so the surface — and the panel — is one height whatever is on show.
struct HostFormView: View {

    @Bindable var model: HostFormModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.loose) {
            SectionHeader(title: isCreating ? "New host" : "Edit host")

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.regular) {
                    field(.patterns, label: isCreating ? "Host alias" : "Host patterns", text: $model.draft.patterns, prompt: "bastion")
                    field(.hostName, label: "HostName", text: $model.draft.hostName, prompt: "bastion.example.com")

                    HStack(alignment: .top, spacing: Spacing.snug) {
                        field(.user, label: "User", text: $model.draft.user, prompt: "alice")
                        field(.port, label: "Port", text: $model.draft.port, prompt: "22")
                    }

                    keyPicker
                }
                // Keeps the scroll indicator off the field chrome, as the key form does.
                .padding(.trailing, Spacing.snug)
                .padding(.bottom, Spacing.snug)
            }

            footer
        }
        .frame(width: PanelMetrics.contentWidth, height: PanelMetrics.surfaceHeight, alignment: .top)
    }

    private var isCreating: Bool { model.mode == .create }

    // MARK: - Fields

    /// An editable field, or the value and the reason it cannot be edited here.
    @ViewBuilder
    private func field(_ field: HostDraftField, label: String, text: Binding<String>, prompt: String) -> some View {
        if let reason = model.readOnlyReason(for: field) {
            ReadOnlyHostField(label: label, value: text.wrappedValue, reason: reason)
        } else {
            LabeledField(label: label, text: text, validation: model.fieldValidation(for: field), prompt: prompt)
        }
    }

    // MARK: - Key

    private var keyPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text("Key")
                .font(Typography.fieldLabel)
                .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))

            if let message = model.noKeysMessage {
                StatusIndicator(role: .inProgress, message: message)
            }

            BoundedList(
                elements: model.keyChoices,
                selection: Binding(
                    get: { model.draft.keyChoice },
                    set: { choice in choice.map(model.select) }
                ),
                emptyState: EmptyStateContent(message: "No keys to choose from", symbolName: "key"),
                maximumHeight: PanelMetrics.keyPickerHeight
            ) { option in
                HostKeyChoiceRowView(option: option)
            }
            .accessibilityLabel("Key")

            // Advisory only: a shared key is the user's call, and nothing here asks again.
            if let status = model.selectedKeyStatus {
                StatusIndicator(role: .warning, message: status)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            if model.isSaving {
                StatusIndicator(role: .inProgress, message: "Saving…")
            }

            HStack(spacing: Spacing.snug) {
                Button("Cancel") { model.discard() }
                    .accessibilityLabel("Cancel and return to the host list")

                Spacer(minLength: 0)

                submitButton
            }
        }
    }

    /// Gated through the confirming style when an earlier block would take precedence, so the
    /// user reads which one before proceeding. The confirming style engages only for a
    /// destructive role, which is why the role changes with the warning.
    @ViewBuilder private var submitButton: some View {
        let title = isCreating ? "Create" : "Save"
        if let warning = model.placementWarning {
            Button(title, role: .destructive) { Task { await model.submit() } }
                .disabled(!model.canSubmit)
                .buttonStyle(.confirming(title: warning.title, message: warning.message))
                .accessibilityLabel(isCreating ? "Create the host" : "Save the host")
        } else {
            Button(title) { Task { await model.submit() } }
                .disabled(!model.canSubmit)
                .accessibilityLabel(isCreating ? "Create the host" : "Save the host")
        }
    }
}

/// A value the form shows but will not change, with why.
private struct ReadOnlyHostField: View {
    let label: String
    let value: String
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(label)
                .font(Typography.fieldLabel)
                .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))

            CodeText(text: value, lineLimit: 1)

            Text(reason)
                .font(Typography.fieldMessage)
                .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value). Read-only. \(reason)")
    }
}

#if DEBUG
#Preview("Create") {
    let models = HostPreviewFixtures.models(config: HostPreviewFixtures.sampleConfig)
    return HostFormView(model: models.form)
        .task {
            await models.load()
            models.form.beginCreate()
        }
        .padding(PanelMetrics.contentInset)
        .frame(width: PanelMetrics.width)
}

#Preview("Edit, with a shared key selected") {
    let models = HostPreviewFixtures.models(config: HostPreviewFixtures.sampleConfig)
    return HostFormView(model: models.form)
        .task {
            await models.load()
            if let web = models.configuration.entries.first(where: { $0.displayName == "web" }) {
                models.form.beginEdit(web)
            }
        }
        .padding(PanelMetrics.contentInset)
        .frame(width: PanelMetrics.width)
}

#Preview("Edit, read-only value and an unresolvable key") {
    let models = HostPreviewFixtures.models(config: "Host db\n    HostName one\n    HostName two\n    IdentityFile ~/keys/%h\n")
    return HostFormView(model: models.form)
        .task {
            await models.load()
            if let db = models.configuration.entries.first {
                models.form.beginEdit(db)
            }
        }
        .padding(PanelMetrics.contentInset)
        .frame(width: PanelMetrics.width)
}

#Preview("Create, with a placement warning") {
    let models = HostPreviewFixtures.models(
        config: "Include work\n\nHost *\n",
        files: ["work": "Host *.corp\n    User corp\n"]
    )
    return HostFormView(model: models.form)
        .task {
            await models.load()
            models.form.beginCreate()
            models.form.draft.patterns = "db.corp"
        }
        .padding(PanelMetrics.contentInset)
        .frame(width: PanelMetrics.width)
}
#endif
