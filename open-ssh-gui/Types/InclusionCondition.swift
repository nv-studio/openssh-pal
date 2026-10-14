import Foundation

/// The block an `Include` directive sits inside, which decides when the file it names applies.
nonisolated enum InclusionCondition: Sendable, Equatable {
    /// Inside a `Host` block: the included file applies only when these patterns match.
    case host([HostPattern])

    /// Inside a `Match` block, whose criteria cannot be evaluated without a connection.
    case match
}
