import Foundation
import Observation

/// Owns the launch-scoped resolution outcome and the status the menu bar renders.
///
/// No initializer parameter has a default value. Forgetting to inject one is then a compile
/// error rather than a silent fallback to the real file system or the real process
/// environment — which, for a component whose job is to point at `~/.ssh`, is the
/// difference between a failing build and a developer's real SSH directory being read.
@MainActor
@Observable
final class SSHDirectoryStatusModel {

    private(set) var status: SSHDirectoryStatus = .resolving

    private let resolver: SSHDirectoryResolver
    private let launchEnvironment: LaunchEnvironment
    private let homeDirectory: URL
    private let reader: SSHDirectoryReading

    /// The memoized resolution outcome. Empty until the first `refresh()`.
    ///
    /// This property is the sole mechanism upholding "resolved once per launch": a
    /// `MenuBarExtra` panel can open many times and each open drives `refresh()` again.
    /// Resolution cannot instead happen at construction time, because validating an override
    /// is asynchronous and a SwiftUI `App` initializer is not.
    private var resolution: Result<SSHDirectory, SSHDirectoryResolutionError>?

    init(
        resolver: SSHDirectoryResolver,
        launchEnvironment: LaunchEnvironment,
        homeDirectory: URL,
        reader: SSHDirectoryReading
    ) {
        self.resolver = resolver
        self.launchEnvironment = launchEnvironment
        self.homeDirectory = homeDirectory
        self.reader = reader
    }

    /// Resolves on the first call only, then re-probes readability on every call.
    ///
    /// Never throws: every failure becomes a status case instead, which is what keeps the
    /// app running and quittable when the directory is missing or unreadable.
    func refresh() async {
        let resolution = await memoizedResolution()

        switch resolution {
        case .failure(let error):
            status = .unresolved(error)
        case .success(let directory):
            status = await probeReadability(of: directory)
        }
    }

    private func memoizedResolution() async -> Result<SSHDirectory, SSHDirectoryResolutionError> {
        if let resolution { return resolution }
        let resolved = await resolver.resolve(
            launchEnvironment: launchEnvironment,
            homeDirectory: homeDirectory
        )
        resolution = resolved
        return resolved
    }

    /// Re-probes on every refresh, so a directory that appears, disappears or loses
    /// permissions while the app runs is reflected the next time the panel opens.
    ///
    /// The listing is the probe and its result is deliberately discarded: only success or
    /// failure is observed, so no file name from the SSH directory is ever retained. A
    /// cheaper existence check would not do, because it cannot tell permission denial from
    /// absence and the user needs the reason.
    private func probeReadability(of directory: SSHDirectory) async -> SSHDirectoryStatus {
        do {
            _ = try await reader.entries(in: directory.url)
            return .reachable(directory)
        } catch {
            return .unreadable(directory, error)
        }
    }
}
