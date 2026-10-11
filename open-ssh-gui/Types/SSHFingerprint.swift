import Foundation

/// A public key's fingerprint, in the form OpenSSH's own tooling prints it.
///
/// A wrapper rather than a bare `String` so a fingerprint cannot be confused with any other
/// text in the model, and so the one place that composes it — the parser — is the only place
/// that knows the format.
nonisolated struct SSHFingerprint: Equatable, Hashable, Sendable {
    let value: String

    init(value: String) {
        self.value = value
    }
}
