import SwiftUI

/// The menu bar panel: a tab bar, the selected tab's surface, a notice and Quit, at one fixed
/// size.
///
/// **The exact height is the mechanism, not a styling choice.** `menuBarExtraStyle(.window)`
/// sizes its panel to the content, so a height that settles after the first layout pass is
/// what AppKit reports as `_NSDetectedLayoutRecursion` — and a scrolling region inside a
/// content-sized panel is reported to lay out correctly on the first open and collapse on
/// later ones. Every region here is a fixed height, and every tab's surface is the same one,
/// which makes both unreachable rather than worked around — and means switching tabs cannot
/// resize the panel.
///
/// The selected tab is the only state held here; what a switch does to the forms behind it is
/// `PanelNavigator`'s.
struct PanelView: View {

    let status: SSHDirectoryStatusModel
    let keys: SSHKeyListModel
    let newKey: NewKeyFormModel
    let configuration: SSHConfigModel
    let hostForm: HostFormModel

    @State private var tab = PanelTab.initial

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            TabBar(label: "Sections", options: PanelTab.allCases, selection: selection, title: \.title)

            surface

            noticeRegion

            Divider()

            // Outside every tab on purpose: an agent-mode app has no Dock icon and no menu of
            // its own, so this is the user's only way out and it must never be scrolled off or
            // left behind on another tab. The destructive role is how the design system is
            // told to colour it as a departure, rather than tinting it here.
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .accessibilityLabel("Quit OpenSSH Pal")
        }
        .padding(PanelMetrics.contentInset)
        .frame(width: PanelMetrics.width, height: PanelMetrics.height, alignment: .top)
        // Every open re-reads both the keys and the configuration, so an edit made in a text
        // editor while the app was running is what the user sees. Then a generation that
        // finished while the panel was dismissed is adopted: its `completion` changed with no
        // view to observe it, so an `onChange` alone would lose it.
        .task {
            await keys.refresh()
            await configuration.refresh()
            await adoptCompletion()
        }
        .onChange(of: newKey.completion) { _, _ in Task { await adoptCompletion() } }
    }

    private var navigator: PanelNavigator {
        PanelNavigator(keys: keys, newKey: newKey, hostForm: hostForm)
    }

    /// The tab bar's binding: every switch goes through the navigator first.
    private var selection: Binding<PanelTab> {
        Binding(
            get: { tab },
            set: { next in
                navigator.select(next, leaving: tab)
                tab = next
            }
        )
    }

    @ViewBuilder private var surface: some View {
        switch tab {
        case .keys:
            SSHKeyListView(model: keys, status: status)
        case .hosts:
            HostsTabView(configuration: configuration, keys: keys, form: hostForm)
        case .newKey:
            // No fallback. If nothing resolved there is nowhere safe to write, and the whole
            // point of the resolver's no-fallback rule is that a missing directory must never
            // quietly become the user's real one.
            if keys.resolvedDirectory != nil {
                NewKeyFormView(model: newKey) { selection.wrappedValue = .keys }
            } else {
                SSHDirectoryStatusView(model: status)
                    .frame(width: PanelMetrics.contentWidth, height: PanelMetrics.surfaceHeight, alignment: .top)
            }
        }
    }

    /// The active tab's last outcome, in a slot that is occupied whether or not there is one —
    /// so a confirmation appearing never changes the panel's height.
    private var noticeRegion: some View {
        Group {
            switch tab {
            case .keys:
                if let notice = keys.notice {
                    StatusIndicator(role: notice.role, message: notice.message)
                } else if keys.isRefreshing {
                    StatusIndicator(role: .inProgress, message: "Reading the SSH directory…")
                }
            case .hosts:
                if let notice = configuration.notice {
                    StatusIndicator(role: notice.role, message: notice.message)
                } else if configuration.isRefreshing {
                    StatusIndicator(role: .inProgress, message: "Reading the SSH configuration…")
                }
            case .newKey:
                // The form reports its own progress and failure beside its controls.
                EmptyView()
            }
        }
        .frame(width: PanelMetrics.contentWidth, height: PanelMetrics.noticeHeight, alignment: .topLeading)
    }

    private func adoptCompletion() async {
        if let next = await navigator.adoptCompletion() {
            tab = next
        }
    }
}
