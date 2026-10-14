import SwiftUI

/// The Hosts tab: the list, or a form in its place.
///
/// The form replaces the list inside the tab rather than opening anywhere else: the panel has no
/// key window for a sheet, and the tab bar stays visible above whichever is shown.
struct HostsTabView: View {

    let configuration: SSHConfigModel
    let keys: SSHKeyListModel
    let form: HostFormModel

    var body: some View {
        if form.mode == nil {
            HostListView(configuration: configuration, keys: keys, form: form)
        } else {
            HostFormView(model: form)
        }
    }
}
