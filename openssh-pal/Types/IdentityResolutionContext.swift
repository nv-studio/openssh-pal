import Foundation

/// What resolving a configured path needs to know without a connection.
///
/// `isDefaultDirectory` is computed from a default directory the caller supplies rather than
/// from a name spelled here: the `.ssh` name belongs to `SSHDirectoryResolver`, and this layer
/// depends on nothing.
nonisolated struct IdentityResolutionContext: Sendable, Equatable {
    let homeDirectory: URL
    let sshDirectory: SSHDirectory
    let userName: String

    /// Whether the resolved directory is the one OpenSSH uses by default. When it is not, the
    /// app is running under an override and every read and write is confined to it.
    let isDefaultDirectory: Bool

    init(homeDirectory: URL, sshDirectory: SSHDirectory, userName: String, defaultDirectory: URL) {
        self.homeDirectory = homeDirectory
        self.sshDirectory = sshDirectory
        self.userName = userName
        isDefaultDirectory = Self.normalizedPath(of: sshDirectory.url) == Self.normalizedPath(of: defaultDirectory)
    }

    /// Whether `url` lies strictly inside the resolved directory, compared by path segment so
    /// that `/a/keys-other` is not taken to be inside `/a/keys`.
    func contains(_ url: URL) -> Bool {
        let directory = Self.normalizedPath(of: sshDirectory.url)
        let candidate = Self.normalizedPath(of: url)
        return candidate.hasPrefix(directory == "/" ? "/" : directory + "/") && candidate != directory
    }

    /// One spelling per location: dot segments removed and no trailing slash.
    static func normalizedPath(of url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
}
