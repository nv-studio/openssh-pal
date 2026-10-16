import Foundation

/// Why a move or a removal through `SSHKeyWriting` could not complete.
///
/// `destinationExists` is its own case because it is the condition that protects a bystander
/// file: the platform refuses to replace an existing destination, and the app reports that
/// refusal rather than retrying over it.
///
/// Absence and denial are separate for the same reason `FileAccessError` separates them — the
/// user's next action differs, and an existence check cannot tell them apart.
nonisolated enum SSHKeyWriteError: Error, Equatable, Sendable {
    case destinationExists(URL)
    case notFound(URL)
    case accessDenied(URL)
    case failed(URL)

    /// The file the operation concerned.
    var url: URL {
        switch self {
        case .destinationExists(let url), .notFound(let url), .accessDenied(let url), .failed(let url):
            url
        }
    }

    /// A reason fit to show the user.
    ///
    /// Each reason names the **file**, not its path. That is a deliberate departure from
    /// `FileAccessError`'s full-path reasons: a path here would often be a private key's
    /// path, which no user-facing message may carry. The file name is what the user needs in
    /// order to act, and the directory is already on screen.
    var reason: String {
        switch self {
        case .destinationExists(let url):
            "\(url.lastPathComponent) already exists."
        case .notFound(let url):
            "\(url.lastPathComponent) is no longer there."
        case .accessDenied(let url):
            "Permission denied for \(url.lastPathComponent)."
        case .failed(let url):
            "\(url.lastPathComponent) could not be changed."
        }
    }
}
