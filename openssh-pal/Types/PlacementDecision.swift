import Foundation

/// Where a new block goes, and what will still take precedence over it.
nonisolated struct PlacementDecision: Sendable, Equatable {
    /// Always in `config`.
    let point: InsertionPoint
    let precedingMatches: [PrecedingMatch]
}
