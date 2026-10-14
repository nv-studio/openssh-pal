import Foundation

/// Everything the host list can be showing.
///
/// "No configuration file" and "could not be read" are separate cases because telling a user
/// they have no hosts when the app could not look would be worse than saying nothing.
nonisolated enum SSHConfigState: Sendable, Equatable {
    /// The first load has not finished.
    case loading

    /// Read, possibly with issues in included files.
    case loaded(SSHConfiguration)

    /// The directory was read and holds no `config`.
    case noConfigFile

    /// `config`, or the directory holding it, exists but could not be read.
    case unreadable(FileAccessError)

    /// No directory resolved at all, because an override was rejected.
    case noDirectory(SSHDirectoryResolutionError)

    var configuration: SSHConfiguration? {
        guard case .loaded(let configuration) = self else { return nil }
        return configuration
    }

    /// Why there is no list, or `nil` where there is one.
    var failureReason: String? {
        switch self {
        case .loading, .loaded, .noConfigFile: nil
        case .unreadable(let error): error.reason
        case .noDirectory(let error): error.reason
        }
    }
}
