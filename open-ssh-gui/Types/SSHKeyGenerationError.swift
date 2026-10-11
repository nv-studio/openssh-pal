import Foundation

/// Why `ssh-keygen` did not produce the key pair that was asked for.
///
/// `outputMismatch` exists because an acceptance gate that only checked whether files
/// appeared would still accept a key of the wrong type. Exit status alone is not treated as
/// proof of success anywhere in this feature.
nonisolated enum SSHKeyGenerationError: Error, Equatable, Sendable {

    /// The tool is not at the path it was given, or could not be executed.
    case toolUnavailable(URL)

    /// The target directory was gone when generation was confirmed. Reported rather than
    /// created: creating `~/.ssh` behind the user's back is not this app's decision.
    case directoryMissing(URL)

    /// The tool ran and exited non-zero. `detail` is its own diagnostic output, which never
    /// carries the passphrase: the passphrase arrives on standard input and `ssh-keygen`
    /// does not echo it.
    case toolFailed(status: Int32, detail: String)

    /// The tool exited zero without writing a file it was supposed to write.
    case outputMissing(URL)

    /// A key was written, but not of the type that was requested.
    case outputMismatch(expected: SSHKeyType, actual: SSHKeyAlgorithm)

    /// A public key file appeared but could not be read as a key.
    ///
    /// Distinct from `outputMissing`, which would tell the user a file is absent when it is
    /// there, and from `outputMismatch`, which needs an algorithm to name. It is reachable:
    /// a tool that exits zero having written a truncated file would land here.
    case outputUnreadable(URL)

    /// The tool neither finished nor failed within the bound.
    case timedOut

    /// A reason fit to show the user.
    ///
    /// As with `SSHKeyWriteError`, a reason names a file rather than a path, and the target
    /// directory is not spelled out — a generated key's path is a private key's path.
    var reason: String {
        switch self {
        case .toolUnavailable(let url):
            "\(url.lastPathComponent) could not be run, so keys cannot be generated."
        case .directoryMissing:
            "The SSH directory does not exist."
        case .toolFailed(let status, let detail):
            detail.isEmpty
                ? "ssh-keygen failed with status \(status)."
                : "ssh-keygen failed: \(detail)"
        case .outputMissing(let url):
            "ssh-keygen did not write \(url.lastPathComponent)."
        case .outputUnreadable(let url):
            "ssh-keygen wrote \(url.lastPathComponent), but it could not be read as a key."
        case .outputMismatch(let expected, let actual):
            "ssh-keygen produced a \(actual.wireName) key instead of \(expected.keygenTypeName)."
        case .timedOut:
            "ssh-keygen timed out."
        }
    }
}
