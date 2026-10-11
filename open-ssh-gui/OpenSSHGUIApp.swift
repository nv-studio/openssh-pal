import SwiftUI

/// The application entry point and the one composition root.
///
/// This is the only place that reads `ProcessInfo`, asks the file system for the home
/// directory, or constructs a concrete adapter. Everything below it receives what it needs
/// through an initializer, which is what keeps the file-access seam fakeable and keeps views
/// away from the file system.
///
/// `MenuBarExtra` is the sole scene. With no window scene declared, the app opens no window
/// at launch; the absence of a Dock icon is a separate concern, handled by `LSUIElement` in
/// the build settings.
@main
struct OpenSSHGUIApp: App {

    /// Held as `@State` so SwiftUI keeps one set of models for the lifetime of the launch
    /// rather than rebuilding them — which is what makes the status model's memoized
    /// resolution meaningful, and what lets a generation outlive a panel dismissal.
    @State private var status: SSHDirectoryStatusModel
    @State private var keys: SSHKeyListModel
    @State private var newKey: NewKeyFormModel

    /// Where `ssh-keygen` lives.
    ///
    /// An absolute path, resolved nowhere else. A `PATH` lookup would let a hijacked `PATH`
    /// choose the binary that receives the user's passphrase, so the path is named here once
    /// and injected.
    private static let keygenURL = URL(filePath: "/usr/bin/ssh-keygen")

    init() {
        let reader = FileSystemSSHDirectoryReader()
        let writer = FileSystemSSHKeyWriter()

        // Resolution deliberately does not happen here. Validating an override is
        // asynchronous and a scene initializer is not, so the once-per-launch guarantee
        // lives in the model's memoization instead.
        let status = SSHDirectoryStatusModel(
            resolver: SSHDirectoryResolver(reader: reader),
            launchEnvironment: LaunchEnvironment(processInfo: .processInfo),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            reader: reader
        )

        self.status = status

        keys = SSHKeyListModel(
            status: status,
            reader: reader,
            writer: writer,
            clipboard: PasteboardClipboardWriter()
        )

        newKey = NewKeyFormModel(
            generator: ProcessSSHKeyGenerator(
                toolURL: Self.keygenURL,
                reader: reader,
                writer: writer,
                parser: SSHPublicKeyParser()
            ),
            // Asked for here because the process is the only source for it, and this is the
            // only place permitted to ask.
            defaultComment: Self.defaultComment()
        )
    }

    /// The comment `ssh-keygen` would have written: the user on this machine.
    private static func defaultComment() -> String {
        let user = NSUserName()
        let host = ProcessInfo.processInfo.hostName
            .split(separator: ".")
            .first
            .map(String.init) ?? "mac"
        return "\(user)@\(host)"
    }

    var body: some Scene {
        MenuBarExtra("open-ssh-gui", systemImage: "key") {
            PanelView(status: status, keys: keys, form: newKey)
                // Applied once, here, and inherited by every descendant control. This is the
                // line that makes the project's appearance impossible for a later call site
                // to bypass: a plain `Button` written anywhere below picks it up without
                // knowing it exists.
                //
                // `ConfirmingButtonStyle` is deliberately *not* applied here. A primitive
                // button style replaces activation for every descendant button, including the
                // ones it builds itself, so applying it globally would recurse — and would
                // also put a confirmation in front of every button in the app.
                .buttonStyle(.panelPlain)
                .labelStyle(.panel)
                .labeledContentStyle(.panel)
                .toggleStyle(.panel)
        }
        .menuBarExtraStyle(.window)
    }
}
