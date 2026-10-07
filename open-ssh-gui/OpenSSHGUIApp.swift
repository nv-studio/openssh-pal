import SwiftUI

/// The application entry point and the one composition root.
///
/// This is the only place that reads `ProcessInfo` or asks the file system for the home
/// directory, and the only place that constructs a concrete adapter. Everything below it
/// receives what it needs through an initializer, which is what keeps the file-access seam
/// fakeable and keeps views away from the file system.
///
/// `MenuBarExtra` is the sole scene. With no window scene declared, the app opens no window
/// at launch; the absence of a Dock icon is a separate concern, handled by `LSUIElement` in
/// the build settings.
@main
struct OpenSSHGUIApp: App {

    /// Held as `@State` so SwiftUI keeps one model for the lifetime of the launch rather
    /// than rebuilding it — which is what makes the model's memoized resolution meaningful.
    ///
    /// Retained but not presented while the showcase occupies the panel. The wiring below is the
    /// verified composition of the shipped foundation; rebuilding it later from scratch would be
    /// worse than leaving it in place for the spec that restores `SSHDirectoryStatusView`.
    @State private var status: SSHDirectoryStatusModel

    init() {
        let reader = FileSystemSSHDirectoryReader()

        // Resolution deliberately does not happen here. Validating an override is
        // asynchronous and a scene initializer is not, so the once-per-launch guarantee
        // lives in the model's memoization instead.
        status = SSHDirectoryStatusModel(
            resolver: SSHDirectoryResolver(reader: reader),
            launchEnvironment: LaunchEnvironment(processInfo: .processInfo),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            reader: reader
        )
    }

    var body: some Scene {
        MenuBarExtra("open-ssh-gui", systemImage: "star") {
            // TEMPORARY: the design system's showcase occupies the panel for the duration of the
            // `design-system` spec. Deleting `Showcase/` and restoring
            // `SSHDirectoryStatusView(model: status)` here is the whole of its removal.
            ShowcasePanel()
                // Applied once, here, and inherited by every descendant control. This is the line
                // that makes the project's appearance impossible for a later call site to bypass:
                // a plain `Button` written anywhere below picks it up without knowing it exists.
                //
                // `ConfirmingButtonStyle` is deliberately *not* applied here. A primitive button
                // style replaces activation for every descendant button, including the one it
                // builds itself, so applying it globally would recurse — and would also put a
                // confirmation in front of every button in the app.
                .buttonStyle(.panelPlain)
                .labelStyle(.panel)
                .labeledContentStyle(.panel)
                .toggleStyle(.panel)
        }
        .menuBarExtraStyle(.window)
    }
}
