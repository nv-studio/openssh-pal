import Foundation

/// Produces the one SSH directory this launch will use, or a typed failure.
///
/// The home directory and the launch environment arrive as parameters rather than being
/// read from the process, which is what makes every rule below testable without touching
/// the real home directory. The resolver also never interprets `~` itself; it takes the
/// home directory the file system reported.
///
/// The resolver is stateless and makes no once-per-launch promise of its own — that
/// guarantee lives in `SSHDirectoryStatusModel`, which memoizes the outcome.
struct SSHDirectoryResolver {

    /// The name of the SSH directory inside the home directory. Nothing else in the app
    /// knows this string.
    static let directoryName = ".ssh"

    private let reader: SSHDirectoryReading

    init(reader: SSHDirectoryReading) {
        self.reader = reader
    }

    /// Resolves the SSH directory for this launch.
    ///
    /// A failure is returned rather than thrown because a bad override is an expected
    /// launch outcome, not an exception.
    func resolve(
        launchEnvironment: LaunchEnvironment,
        homeDirectory: URL
    ) async -> Result<SSHDirectory, SSHDirectoryResolutionError> {
        guard let overridePath = launchEnvironment.overridePath else {
            // Deliberately unvalidated: an absent SSH directory is a legitimate first-run
            // state, and must surface as unreadable rather than as a resolution failure.
            return .success(SSHDirectory(url: defaultDirectory(inHome: homeDirectory)))
        }
        return await validated(overridePath)
    }

    private func defaultDirectory(inHome homeDirectory: URL) -> URL {
        homeDirectory.appending(path: Self.directoryName)
    }

    /// Accepts an override only once it is known to name an existing directory.
    ///
    /// There is deliberately no fallback to the home directory here. A mistyped override
    /// silently resolving to the developer's real SSH directory is the accident this whole
    /// feature exists to prevent, so a bad override fails loudly and names itself.
    private func validated(_ overridePath: String) async -> Result<SSHDirectory, SSHDirectoryResolutionError> {
        // Built without a directory hint so the resulting URL carries no trailing slash,
        // whether it ends up naming an accepted directory or a rejected path. One spelling
        // keeps the value comparable and keeps the displayed path clean.
        let url = URL(filePath: overridePath).standardizedFileURL

        if await reader.directoryExists(at: url) {
            return .success(SSHDirectory(url: url))
        }
        if await reader.fileExists(at: url) {
            return .failure(.overridePathIsNotADirectory(url))
        }
        return .failure(.overridePathDoesNotExist(url))
    }
}
