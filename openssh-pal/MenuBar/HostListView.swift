import SwiftUI

/// The host list surface: every `Host` block, the selected one's details, and its actions.
///
/// Holds no logic and reaches nothing. Every value comes from the injected models — the words
/// from `HostEntryPresentation`, the verdicts from `SSHConfigModel` — and every appearance from
/// the design system.
///
/// The surface is an exact height, so switching to the form or another tab cannot change the
/// panel's size.
struct HostListView: View {

    let configuration: SSHConfigModel
    let keys: SSHKeyListModel
    let form: HostFormModel

    @State private var selection: HostEntryID?

    /// One line, reserved whether or not there is an issue, so an issue appearing never moves
    /// the list.
    @ScaledMetric(relativeTo: .caption) private var issueHeight = PanelMetrics.fieldMessageHeight

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.loose) {
            VStack(alignment: .leading, spacing: Spacing.snug) {
                SectionHeader(title: "Hosts")

                issueLine
                    .frame(height: issueHeight, alignment: .leading)

                listRegion
                    .frame(height: PanelMetrics.hostListHeight, alignment: .top)
            }

            detailRegion

            actionsRegion

            Spacer(minLength: 0)
        }
        .frame(width: PanelMetrics.contentWidth, height: PanelMetrics.surfaceHeight, alignment: .top)
    }

    // MARK: - Issues

    @ViewBuilder private var issueLine: some View {
        if let summary = configuration.issueSummary {
            Label {
                Text(summary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: StatusRole.warning.symbolName)
                    .foregroundStyle(ColorRoleAppearance.style(for: .warning))
            }
            .font(Typography.fieldMessage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(summary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Warning: \(summary)")
        }
    }

    // MARK: - The hosts

    @ViewBuilder private var listRegion: some View {
        switch configuration.state {
        case .loading:
            StatusIndicator(role: .inProgress, message: "Reading the SSH configuration…")
        case .noConfigFile:
            // Distinct from "no hosts": there is no file at all, and creating a host makes one.
            EmptyState(content: EmptyStateContent(message: "No configuration file", symbolName: "doc"))
        case .unreadable, .noDirectory:
            // Not the empty state: saying there are no hosts when the app could not look would
            // be worse than saying nothing.
            StatusIndicator(role: .failure, message: configuration.state.failureReason ?? "")
        case .loaded:
            BoundedList(
                elements: presentations,
                selection: $selection,
                emptyState: EmptyStateContent(message: "No hosts configured", symbolName: "server.rack"),
                maximumHeight: PanelMetrics.hostListHeight
            ) { presentation in
                HostRowView(presentation: presentation, isOperating: configuration.operation.entry == presentation.id)
            }
        }
    }

    /// The selected host's attributes. Reserved whether or not anything is selected, so
    /// selecting a host does not move the controls beneath it.
    private var detailRegion: some View {
        Group {
            if let presentation = selectedPresentation {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    if let warning = presentation.sharingWarning {
                        StatusIndicator(role: .warning, message: warning)
                    } else if let reason = presentation.readOnlyReason {
                        StatusIndicator(role: .warning, message: reason)
                    }

                    LabeledContent("Address", value: presentation.summary)
                    LabeledContent("Key", value: presentation.keySummary)
                    LabeledContent("File", value: presentation.file)
                }
            } else if !presentations.isEmpty {
                StatusIndicator(role: .inProgress, message: "Select a host to edit or delete it.")
            }
        }
        .frame(height: PanelMetrics.hostDetailHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Actions

    private var actionsRegion: some View {
        HStack(spacing: Spacing.snug) {
            if let entry = selectedEntry, let presentation = selectedPresentation {
                Button("Edit") { form.beginEdit(entry) }
                    .disabled(presentation.isReadOnly)
                    .accessibilityLabel("Edit Host \(presentation.title)")

                Button("Delete", role: .destructive) {
                    Task { _ = await configuration.delete(entry) }
                }
                .disabled(presentation.isReadOnly)
                .buttonStyle(
                    .confirming(
                        title: configuration.deletionTitle(for: entry),
                        message: configuration.deletionMessage(for: entry)
                    )
                )
                .accessibilityLabel("Delete Host \(presentation.title)")
            }

            Spacer(minLength: 0)

            Button("New host") { form.beginCreate() }
                .disabled(!configuration.canCreate)
                .accessibilityLabel("Add a new host")
        }
        .disabled(configuration.operation.isInFlight)
    }

    // MARK: - Selection

    private var presentations: [HostEntryPresentation] {
        configuration.presentations(for: keys.state.pairs)
    }

    private var selectedPresentation: HostEntryPresentation? {
        presentations.first { $0.id == selection }
    }

    private var selectedEntry: HostEntry? {
        configuration.entries.first { $0.id == selection }
    }
}

#if DEBUG
#Preview("Hosts, shared keys, an issue and a pattern entry") {
    let models = HostPreviewFixtures.models(config: HostPreviewFixtures.sampleConfig)
    return HostListView(configuration: models.configuration, keys: models.keys, form: models.form)
        .task { await models.load() }
        .padding(PanelMetrics.contentInset)
        .frame(width: PanelMetrics.width)
}

#Preview("No hosts configured") {
    let models = HostPreviewFixtures.models(config: "ServerAliveInterval 30\n")
    return HostListView(configuration: models.configuration, keys: models.keys, form: models.form)
        .task { await models.load() }
        .padding(PanelMetrics.contentInset)
        .frame(width: PanelMetrics.width)
}

#Preview("No configuration file") {
    let models = HostPreviewFixtures.models(config: nil)
    return HostListView(configuration: models.configuration, keys: models.keys, form: models.form)
        .task { await models.load() }
        .padding(PanelMetrics.contentInset)
        .frame(width: PanelMetrics.width)
}

#Preview("Still loading") {
    let models = HostPreviewFixtures.models(config: HostPreviewFixtures.sampleConfig)
    return HostListView(configuration: models.configuration, keys: models.keys, form: models.form)
        .padding(PanelMetrics.contentInset)
        .frame(width: PanelMetrics.width)
}
#endif
