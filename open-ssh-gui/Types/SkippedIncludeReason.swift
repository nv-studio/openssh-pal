import Foundation

/// Why an `Include` argument was not followed.
nonisolated enum SkippedIncludeReason: Error, Sendable, Equatable {
    /// The path depends on something the app will not guess at.
    case unresolvable(UnresolvableReason)

    /// The path lies outside an override directory, which every read is confined to.
    case outsideOverride

    var description: String {
        switch self {
        case .unresolvable(let reason): "the path \(reason.description)"
        case .outsideOverride: "it is outside the SSH directory this launch is confined to"
        }
    }
}
