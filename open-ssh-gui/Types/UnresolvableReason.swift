import Foundation

/// Why a configured path cannot be resolved without a connection.
///
/// Each case is something the app refuses to guess at. Substituting a value `ssh` would compute
/// differently would associate a host with the wrong key, which is worse than saying nothing.
nonisolated enum UnresolvableReason: Error, Sendable, Equatable, Hashable {
    /// A `%` token whose value depends on the connection, such as `%h` or `%r`.
    case connectionToken(String)

    /// A `${VARIABLE}`. A menu bar app launched by `launchd` does not have the user's shell
    /// environment, so any value it substituted could differ from what `ssh` sees.
    case environmentVariable

    /// `~user/…`, another account's home directory.
    case otherUsersHome

    /// A relative path, which `ssh` resolves against its own working directory.
    case relativePath

    var description: String {
        switch self {
        case .connectionToken(let token): "\(token) depends on the connection"
        case .environmentVariable: "uses an environment variable"
        case .otherUsersHome: "names another user's home directory"
        case .relativePath: "is relative to wherever ssh is run"
        }
    }
}
