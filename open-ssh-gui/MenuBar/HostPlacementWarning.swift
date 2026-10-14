import Foundation

/// What the create form says before adding a block that an earlier one would pre-empt.
nonisolated struct HostPlacementWarning: Sendable, Equatable {
    let title: String
    let message: String
}
