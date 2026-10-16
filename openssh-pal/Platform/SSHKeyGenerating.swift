import Foundation

/// Generation of a key pair, performed by OpenSSH's own tooling.
///
/// A port so the form's success and failure paths can be exercised without launching a
/// process, and so no part of the app other than one adapter knows what `Process` is.
///
/// The passphrase is a separate parameter rather than a field on the request. Nothing in the
/// app therefore holds a value carrying both what to generate and the secret to protect it
/// with.
protocol SSHKeyGenerating: Sendable {

    /// Generates the requested pair inside `directory` and returns the pair that was
    /// actually written.
    ///
    /// The returned pair's attributes are parsed from the file on disk rather than echoed
    /// back from the request, so a tool that produced something else is a failure rather
    /// than a success.
    func generate(
        _ request: SSHKeyGenerationRequest,
        passphrase: Passphrase,
        in directory: SSHDirectory
    ) async throws(SSHKeyGenerationError) -> SSHKeyPair
}
