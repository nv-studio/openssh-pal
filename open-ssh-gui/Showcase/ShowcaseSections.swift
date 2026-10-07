import SwiftUI

/// **TEMPORARY — the next feature spec deletes this directory.**
///
/// One section per component, each in every state its input types can express. Every value shown
/// here is declared in this file: the showcase reads nothing from the SSH directory, so what it
/// demonstrates does not depend on whose machine it runs on.
struct ShowcaseSections: View {

    // The showcase is the *caller*, so it owns all the state the components are driven by. This is
    // the arrangement every real consumer will have.
    @State private var hostName = "bastion.example.com"
    @State private var emptyField = ""
    @State private var compression = true
    @State private var keyType = "ed25519"
    @State private var selectedHost: Int?
    @State private var keyRevealed = false

    private struct Host: Identifiable {
        let id: Int
        let name: String
    }

    private let hosts = (1...9).map { Host(id: $0, name: "host-\($0).example.com") }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.loose) {
            inheritedAppearance
            buttons
            labelsAndRows
            fields
            choices
            statusAndCode
            lists
            secrets
            emptyStates
            densities
        }
    }

    /// The standing check that style propagation works.
    ///
    /// Nothing here applies a style. If these render in the project's appearance, the styles
    /// applied once at the scene root are reaching descendants — which is the entire reason this
    /// layer styles native controls instead of wrapping them.
    private var inheritedAppearance: some View {
        section("Inherited appearance, no local style") {
            Button("A plain Button, styled by inheritance") {}
            Label("A plain Label", systemImage: "wand.and.stars")
            LabeledContent("A plain LabeledContent", value: "styled")
        }
    }

    private var buttons: some View {
        section("Buttons") {
            HStack(spacing: Spacing.snug) {
                Button("Prominent") {}.buttonStyle(.panelProminent)
                Button("Plain") {}.buttonStyle(.panelPlain)
            }
            Button("Disabled") {}.disabled(true)
            Button("Delete key", role: .destructive) {}
            Button("Delete key, confirming", role: .destructive) {}
                .buttonStyle(.confirming)
        }
    }

    private var labelsAndRows: some View {
        section("Labels and rows") {
            Label("Primary emphasis", systemImage: "circle.fill")
                .labelStyle(.panel)
            Label("Secondary emphasis", systemImage: "circle")
                .labelStyle(.panelSecondary)
            Label(
                "A label long enough to wrap to its line bound and then truncate",
                systemImage: "text.alignleft"
            )
            LabeledContent("Port", value: "22")
            LabeledContent("IdentityFile", value: "~/.ssh/id_ed25519")
        }
    }

    private var fields: some View {
        section("Text input") {
            LabeledField(label: "HostName", text: $hostName)
            LabeledField(
                label: "HostName",
                text: $emptyField,
                validation: .invalid("HostName is required"),
                prompt: "required"
            )
        }
    }

    private var choices: some View {
        section("Choices") {
            Toggle("Compression", isOn: $compression)
            ChoiceRow(
                label: "Key type",
                options: ["ed25519", "rsa", "ecdsa"],
                selection: $keyType
            ) { $0 }
        }
    }

    private var statusAndCode: some View {
        section("Status and code") {
            StatusIndicator(role: .success, message: "Reachable")
            StatusIndicator(role: .warning, message: "Permission denied")
            StatusIndicator(role: .failure, message: "The override path is not a directory")
            StatusIndicator(role: .inProgress, message: "Resolving…")
            CodeText(text: "~/.ssh/config")
            CodeText(text: "/an/extremely/long/path/that/has/to/truncate/in/the/middle/id_ed25519.pub")
        }
    }

    private var lists: some View {
        section("Lists") {
            Text("populated, bounded, scrolls").font(Typography.fieldMessage)
            BoundedList(
                elements: hosts,
                selection: $selectedHost,
                emptyState: EmptyStateContent(message: "No hosts configured")
            ) { host in
                Text(host.name)
            }

            Text("empty, same component").font(Typography.fieldMessage)
            BoundedList(
                elements: [Host](),
                selection: $selectedHost,
                emptyState: EmptyStateContent(
                    message: "No hosts in this configuration",
                    symbolName: "server.rack"
                )
            ) { host in
                Text(host.name)
            }
        }
    }

    private var secrets: some View {
        section("Secrets") {
            SecretField(
                label: "Private key",
                presentation: keyRevealed
                    ? .revealed("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeFakeFake")
                    : .redacted(placeholderLength: 64),
                onRevealRequested: { keyRevealed = true }
            )
            Text("The caller grants the reveal; the component only asks.")
                .font(Typography.fieldMessage)
                .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))
        }
    }

    private var emptyStates: some View {
        section("Empty states") {
            EmptyState(content: EmptyStateContent(message: "Message only"))
            EmptyState(
                content: EmptyStateContent(
                    message: "With a symbol and an action",
                    symbolName: "key",
                    action: EmptyStateContent.Action(title: "Generate a key pair") {}
                )
            )
        }
    }

    private var densities: some View {
        section("Density override") {
            HStack(alignment: .top, spacing: Spacing.loose) {
                densityColumn("regular")
                densityColumn("compact")
                    .environment(\.panelDensity, .compact)
            }
        }
    }

    private func densityColumn(_ title: String) -> some View {
        DensityColumn(title: title)
    }

    private struct DensityColumn: View {
        let title: String

        @Environment(\.panelDensity) private var density

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.snug * density.spacingScale) {
                Text(title).font(Typography.fieldMessage)
                ForEach(1..<4) { index in
                    Text("row \(index)").font(Typography.control)
                }
            }
        }
    }

    @ViewBuilder
    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            SectionHeader(title: title)
            content()
        }
    }
}
