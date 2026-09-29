import Foundation

/// Why the SSH directory could not be resolved.
///
/// Only an explicit override can fail resolution. An absent default SSH directory is a
/// legitimate first-run state and surfaces as `FileAccessError.directoryNotFound` instead.
enum SSHDirectoryResolutionError: Error, Equatable, Sendable {
    case overridePathDoesNotExist(URL)
    case overridePathIsNotADirectory(URL)

    /// The path the override named, which resolution rejected.
    var url: URL {
        switch self {
        case .overridePathDoesNotExist(let url), .overridePathIsNotADirectory(let url):
            url
        }
    }

    /// A reason fit to show the user, so the menu bar never inspects a system error.
    var reason: String {
        switch self {
        case .overridePathDoesNotExist(let url):
            "No such directory: \(url.path(percentEncoded: false))"
        case .overridePathIsNotADirectory(let url):
            "Not a directory: \(url.path(percentEncoded: false))"
        }
    }
}
