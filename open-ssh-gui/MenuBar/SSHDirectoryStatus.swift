import Foundation

/// Everything the menu bar can report about the SSH directory.
///
/// A closed set of mutually exclusive cases, so a directory that is reachable *and* carries
/// an error is not representable. Each failure case carries the context needed to show the
/// user a reason, which is why no error ever needs to reach the view as an error.
enum SSHDirectoryStatus: Sendable, Equatable {
    /// The first refresh has not finished yet.
    case resolving

    /// The directory resolved and could be listed.
    case reachable(SSHDirectory)

    /// An override named a path that could not be accepted; there is no directory at all.
    case unresolved(SSHDirectoryResolutionError)

    /// The directory resolved but could not be read.
    case unreadable(SSHDirectory, FileAccessError)

    /// The path to show the user: the resolved directory, or the path an override was
    /// rejected for. `nil` only while the first refresh is still in flight.
    ///
    /// This projection lives here rather than in the view so that the view stays a pure
    /// rendering of a value and the mapping stays testable.
    var displayPath: String? {
        switch self {
        case .resolving:
            nil
        case .reachable(let directory), .unreadable(let directory, _):
            directory.url.path(percentEncoded: false)
        case .unresolved(let error):
            error.url.path(percentEncoded: false)
        }
    }

    /// Whether the directory is known to be readable, which is what the reachability
    /// indicator reflects.
    var isReachable: Bool {
        if case .reachable = self { return true }
        return false
    }

    /// The status vocabulary the design system's indicator renders.
    ///
    /// The mapping lives here rather than in the design system, so that layer never learns what an
    /// SSH directory is. An unreadable directory is a *warning* rather than a failure because the
    /// directory exists and the user can usually fix it; a rejected override is a failure because
    /// there is no directory at all.
    var statusRole: StatusRole {
        switch self {
        case .resolving: .inProgress
        case .reachable: .success
        case .unresolved: .failure
        case .unreadable: .warning
        }
    }

    /// The words beside the indicator's icon. Never empty, so the row is never a bare glyph.
    var statusMessage: String {
        switch self {
        case .resolving:
            "Resolving…"
        case .reachable:
            "Reachable"
        case .unresolved(let error):
            error.reason
        case .unreadable(_, let error):
            error.reason
        }
    }

    /// Why the directory is not reachable, shown in place of the indicator. `nil` when there
    /// is nothing to explain.
    var failureReason: String? {
        switch self {
        case .resolving, .reachable:
            nil
        case .unresolved(let error):
            error.reason
        case .unreadable(_, let error):
            error.reason
        }
    }
}
