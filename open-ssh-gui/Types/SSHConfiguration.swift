import Foundation

/// The whole configuration as loaded: `config`, every file it reached, and what went wrong.
nonisolated struct SSHConfiguration: Sendable, Equatable {
    /// In load order. The first is always `config` itself.
    let files: [SSHConfigFile]

    /// Every `Host` block, flattened in the order `ssh` reads them.
    let entries: [HostEntry]

    let issues: [ConfigLoadIssue]

    /// Every expanded `Include` path, so a backup is never placed where `ssh` would read it.
    let includePatterns: [GlobPath]

    /// `config` itself.
    var root: SSHConfigFile? { files.first }

    func file(at url: URL) -> SSHConfigFile? {
        files.first { $0.url == url }
    }

    /// The same configuration with files and entries replaced, for writability discovered
    /// after loading.
    func with(files: [SSHConfigFile], entries: [HostEntry]) -> SSHConfiguration {
        SSHConfiguration(files: files, entries: entries, issues: issues, includePatterns: includePatterns)
    }
}
