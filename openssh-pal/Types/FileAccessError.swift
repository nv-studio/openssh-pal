import Foundation

/// Why a read through `SSHDirectoryReading` could not complete.
///
/// Absence and permission denial are separate cases because the user needs to know which
/// of the two occurred; a plain existence check cannot tell them apart.
nonisolated enum FileAccessError: Error, Equatable, Sendable {
    case directoryNotFound(URL)
    case accessDenied(URL)
    case unreadable(URL)

    /// The path the read was attempted against.
    var url: URL {
        switch self {
        case .directoryNotFound(let url), .accessDenied(let url), .unreadable(let url):
            url
        }
    }

    /// A reason fit to show the user, so the menu bar never inspects a system error.
    var reason: String {
        switch self {
        case .directoryNotFound(let url):
            "Not found: \(url.path(percentEncoded: false))"
        case .accessDenied(let url):
            "Permission denied: \(url.path(percentEncoded: false))"
        case .unreadable(let url):
            "Could not be read: \(url.path(percentEncoded: false))"
        }
    }
}
