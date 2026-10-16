import Foundation

/// What leaving and entering a tab does to the forms behind it.
///
/// The panel view stores only which tab is selected and asks this what a switch means, so the
/// rules — discard on leave, open the key form on enter, adopt a finished generation — are
/// testable without rendering anything.
@MainActor
struct PanelNavigator {

    let keys: SSHKeyListModel
    let newKey: NewKeyFormModel
    let hostForm: HostFormModel

    /// Leaves `current` for `next`.
    ///
    /// A form left behind is discarded without writing anything and without keeping an entered
    /// passphrase. A key generation that is running is the exception: `discard()` leaves it
    /// alone, so it finishes and its outcome is presented when it does.
    func select(_ next: PanelTab, leaving current: PanelTab) {
        guard next != current else { return }

        switch current {
        case .keys: break
        case .hosts: hostForm.discard()
        case .newKey: newKey.discard()
        }

        if next == .newKey { openNewKeyForm() }
    }

    /// Opens the create form against the directory and listing the key list last read.
    ///
    /// Not while a generation runs or its failure is still unread: coming back to the tab
    /// should show those, not a fresh form. And not without a resolved directory, which has no
    /// fallback — the tab shows the directory status instead.
    private func openNewKeyForm() {
        guard !newKey.isGenerating, newKey.failureReason == nil, let directory = keys.resolvedDirectory else { return }
        newKey.begin(in: directory, existing: keys.directoryEntries)
    }

    /// Takes whatever the create form finished with and hands a created pair to the key list.
    ///
    /// - Returns: the tab to show — Keys, where the new pair is — or `nil` when nothing has
    ///   finished.
    func adoptCompletion() async -> PanelTab? {
        guard let completion = newKey.completion else { return nil }

        newKey.acknowledgeCompletion()
        if let pair = completion.createdPair {
            await keys.acknowledge(created: pair)
        }
        return .keys
    }
}
