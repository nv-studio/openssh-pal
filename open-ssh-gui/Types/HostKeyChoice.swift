import Foundation

/// What a host form does with a block's `IdentityFile` lines.
nonisolated enum HostKeyChoice: Hashable, Sendable {
    /// Edit only: leave every `IdentityFile` line exactly as it is.
    case unchanged

    /// No `IdentityFile`, so `ssh` uses its default identities.
    case none

    case pair(SSHKeyName)
}
