import Foundation

/// Where in `config` a new block goes.
nonisolated enum InsertionPoint: Sendable, Equatable {
    /// Immediately before this line, from zero.
    case before(line: Int)
    case end
}
