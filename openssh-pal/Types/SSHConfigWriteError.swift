import Foundation

/// Why a write through `SSHConfigWriting` did not happen.
///
/// After any of these the target is byte-identical to what it was: there is no "partly
/// written" case, because the adapter replaces a file only by renaming a complete copy over it.
nonisolated enum SSHConfigWriteError: Error, Equatable, Sendable {
    /// The file's bytes differ from the baseline the edit was computed from.
    case changedOnDisk(URL)

    /// A file that was to be created already exists.
    case alreadyExists(URL)

    case notFound(URL)
    case accessDenied(URL)

    /// The target, once symbolic links are followed, lies outside the SSH directory.
    case outsideDirectory(URL)

    case failed(URL)

    var url: URL {
        switch self {
        case .changedOnDisk(let url), .alreadyExists(let url), .notFound(let url),
             .accessDenied(let url), .outsideDirectory(let url), .failed(let url):
            url
        }
    }

    /// A reason fit to show the user. Unlike a key's path, a configuration file's path is not
    /// sensitive, so the file is named in full.
    var reason: String {
        let name = url.path(percentEncoded: false)
        return switch self {
        case .changedOnDisk:
            "\(name) changed since it was read, so nothing was written."
        case .alreadyExists:
            "\(name) already exists, so nothing was written."
        case .notFound:
            "\(name) is no longer there."
        case .accessDenied:
            "Permission denied for \(name)."
        case .outsideDirectory:
            "\(name) is outside the SSH directory, so it was not changed."
        case .failed:
            "\(name) could not be written."
        }
    }
}
