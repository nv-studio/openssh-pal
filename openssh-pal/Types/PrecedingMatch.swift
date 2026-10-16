import Foundation

/// A block that matches a new alias and that `ssh` reads before the new block, so the values it
/// sets win under first-obtained-value-wins.
nonisolated struct PrecedingMatch: Sendable, Equatable {
    let entry: HostEntryID
    let displayName: String
    let file: URL

    /// Reached through a `Match` block, which may or may not apply.
    let isConditional: Bool
}
