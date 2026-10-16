import Foundation

/// One `Host` block, as it is declared.
///
/// Only what the block itself says. Values `ssh` would inherit from a `Host *` block, a
/// `Match` block or an include are deliberately absent — computing them is `ssh -G`'s job,
/// and a partial reimplementation would be wrong exactly where the user most needs it right.
nonisolated struct HostEntry: Identifiable, Sendable, Equatable {
    let id: HostEntryID

    /// The header through the line before the next header, or the end of the file.
    let lineRange: Range<Int>

    let patterns: [HostPattern]

    /// The first declaration of each, because the first is the one `ssh` uses.
    let hostName: DeclaredValue?
    let user: DeclaredValue?
    let port: DeclaredValue?

    /// Every `IdentityFile`, in order: unlike the values above, they accumulate.
    let identityFiles: [DeclaredValue]

    /// Keywords the block declares more than once. Clearing the first of a repeated value
    /// would silently promote the second, so the form will not edit one.
    let repeatedKeywords: Set<SSHConfigKeyword>

    let writability: ConfigWritability

    var file: URL { id.file }

    var headerLine: Int { lineRange.lowerBound }

    /// Whether this block describes a policy rather than a host: every pattern is wildcarded
    /// or negated. Such a block is listed, but never counts toward a shared-key warning.
    var isPatternEntry: Bool {
        patterns.allSatisfy { $0.hasWildcard || $0.isNegated }
    }

    /// The patterns as the `Host` line writes them.
    var displayName: String {
        patterns.map(\.token).joined(separator: " ")
    }

    /// What makes two blocks the same host: the same patterns, ignoring order and case. A
    /// `Host github.com` declared twice is one host, not a key shared with itself.
    var hostIdentity: Set<String> {
        Set(patterns.map { $0.token.lowercased() })
    }

    /// The same entry with a different writability, for a downgrade discovered after loading.
    func withWritability(_ writability: ConfigWritability) -> HostEntry {
        HostEntry(
            id: id,
            lineRange: lineRange,
            patterns: patterns,
            hostName: hostName,
            user: user,
            port: port,
            identityFiles: identityFiles,
            repeatedKeywords: repeatedKeywords,
            writability: writability
        )
    }
}
