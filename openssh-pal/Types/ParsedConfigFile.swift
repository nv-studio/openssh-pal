import Foundation

/// Everything one file says, in the order it says it.
nonisolated struct ParsedConfigFile: Sendable, Equatable {
    let file: SSHConfigFile

    /// `Host` blocks only, in file order. A `Match` block never becomes an entry.
    let entries: [HostEntry]

    let includes: [IncludeDirective]

    /// Indices of the lines OpenSSH would reject, from zero.
    let malformedLines: [Int]
}
