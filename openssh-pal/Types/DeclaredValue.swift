import Foundation

/// A value a block declares, and the line that declares it.
nonisolated struct DeclaredValue: Sendable, Equatable {
    let value: String

    /// The line's index in its file, from zero.
    let line: Int
}
