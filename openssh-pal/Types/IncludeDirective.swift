import Foundation

/// An `Include` line, where it is and what governs it.
nonisolated struct IncludeDirective: Sendable, Equatable {
    /// The line's index in its file, from zero.
    let line: Int

    let arguments: [String]

    /// `nil` in the global section.
    let condition: InclusionCondition?
}
