import Foundation

/// An `IdentityFile` value and what it resolves to.
nonisolated struct IdentityReference: Sendable, Equatable {

    /// The value exactly as written, which is what the user is shown whenever it does not
    /// resolve to a listed key.
    let raw: String

    let resolution: Resolution

    nonisolated enum Resolution: Sendable, Equatable {
        case path(URL)

        /// The literal `none`.
        case disabled

        case unresolvable(UnresolvableReason)
    }
}
