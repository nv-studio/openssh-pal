import Foundation

/// Why a public key file's contents could not be read as an OpenSSH public key.
///
/// A parse failure is a state on the entry, not a reason to drop it: the user still needs to
/// be told which file in their SSH directory is not what it appears to be.
nonisolated enum SSHPublicKeyError: Error, Equatable, Sendable {
    /// The file held nothing, or nothing but whitespace.
    case empty

    /// Fewer than the two fields every public key line carries.
    case malformedLine

    /// The second field was not decodable base64.
    case notBase64

    /// The blob decoded but ended inside a length-prefixed field.
    case truncatedBlob

    /// The file itself could not be read, so there were no bytes to parse.
    ///
    /// Never produced by the parser, which is handed bytes. It exists so that an entry whose
    /// public key is present but unreadable is still presented with a reason, rather than
    /// being dropped or shown as malformed — which would say the wrong thing about the file.
    case fileUnreadable

    /// A reason fit to show the user, naming the file it concerns.
    func reason(for fileName: String) -> String {
        switch self {
        case .empty:
            "\(fileName) is empty."
        case .malformedLine:
            "\(fileName) is not an OpenSSH public key."
        case .notBase64:
            "\(fileName) does not hold a decodable key."
        case .truncatedBlob:
            "\(fileName) holds a truncated key."
        case .fileUnreadable:
            "\(fileName) could not be read."
        }
    }
}
