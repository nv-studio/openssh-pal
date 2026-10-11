import SwiftUI

/// The menu bar panel: both surfaces, at one fixed size.
///
/// **The exact height is the mechanism, not a styling choice.** `menuBarExtraStyle(.window)`
/// sizes its panel to the content, so a height that settles after the first layout pass is
/// what AppKit reports as `_NSDetectedLayoutRecursion` — and a scrolling region inside a
/// content-sized panel is reported to lay out correctly on the first open and collapse on
/// later ones. Every region here is a fixed height, which makes both unreachable rather than
/// worked around. Generalising the `reservedStatusHeight` this project already carried from
/// one row pair to the whole panel is the whole of the change.
///
/// The route is a closed enum rather than a `NavigationStack`: the stack's behaviour inside a
/// content-sized `NSPanel` is undocumented and it is the change most likely to bring the
/// recursion back.
struct PanelView: View {

    let status: SSHDirectoryStatusModel
    let keys: SSHKeyListModel
    let form: NewKeyFormModel

    @State private var route: PanelRoute = .keyList

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            surface

            noticeRegion

            Divider()

            // Outside every scrolling region on purpose: an agent-mode app has no Dock icon
            // and no menu of its own, so this is the user's only way out and it must never be
            // scrolled off. The destructive role is how the design system is told to colour
            // it as a departure, rather than tinting it here.
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .accessibilityLabel("Quit open-ssh-gui")
        }
        .padding(Spacing.loose)
        .frame(width: PanelMetrics.width, height: PanelMetrics.height, alignment: .top)
        // Also checked on appear, not only on change: a generation that finished while the
        // panel was dismissed has already changed `completion`, so an `onChange` alone would
        // never see it and the outcome would be lost.
        .task { await adoptCompletion() }
        .onChange(of: form.completion) { _, _ in Task { await adoptCompletion() } }
    }

    @ViewBuilder private var surface: some View {
        switch route {
        case .keyList:
            SSHKeyListView(model: keys, status: status) {
                // No fallback. If nothing resolved there is nowhere safe to write, and the
                // whole point of the resolver's no-fallback rule is that a missing directory
                // must never quietly become the user's real one.
                guard let directory = keys.resolvedDirectory else { return }
                form.begin(in: directory, existing: keys.directoryEntries)
                route = .newKey
            }
        case .newKey:
            NewKeyFormView(model: form) {
                route = .keyList
            }
        }
    }

    /// The outcome of the last operation, in a slot that is occupied whether or not there is
    /// one — so a confirmation appearing never changes the panel's height.
    private var noticeRegion: some View {
        Group {
            if let notice = keys.notice {
                StatusIndicator(role: notice.role, message: notice.message)
            } else if keys.isRefreshing {
                StatusIndicator(role: .inProgress, message: "Reading the SSH directory…")
            }
        }
        .frame(width: PanelMetrics.width, height: PanelMetrics.noticeHeight, alignment: .topLeading)
    }

    /// Takes whatever the create form finished with, returns to the list, and hands a created
    /// pair to the list so it can present it.
    private func adoptCompletion() async {
        guard let completion = form.completion else { return }

        route = .keyList
        form.acknowledgeCompletion()

        if let pair = completion.createdPair {
            await keys.acknowledge(created: pair)
        }
    }
}
