import Foundation

/// Why a supplied key name cannot be used.
///
/// One case per rule, so a caller can tell the user which rule it broke rather than that
/// "the name is invalid". A collision carries the file at risk, because knowing *that* a
/// name is taken is much less useful than knowing which file would have gone.
nonisolated enum SSHKeyNameError: Error, Equatable, Sendable {
    case empty
    case notAPlainFileName(String)
    case endsInPublicKeyExtension(String)
    case reservedByOpenSSH(String)
    case wouldReplace(URL)

    /// A reason fit to show the user, so no view inspects a case of its own accord.
    var reason: String {
        switch self {
        case .empty:
            "The name cannot be empty."
        case .notAPlainFileName:
            "The name cannot contain a path separator or point outside the SSH directory."
        case .endsInPublicKeyExtension:
            "Leave off .pub — it is added to the public key file automatically."
        case .reservedByOpenSSH(let name):
            "\(name) is reserved by OpenSSH."
        case .wouldReplace(let url):
            "\(url.lastPathComponent) already exists and would be replaced."
        }
    }
}
