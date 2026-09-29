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
            SSHDirectoryStatusView(model: status)
        }
        .menuBarExtraStyle(.window)
    }
}
