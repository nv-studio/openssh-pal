import Foundation

/// A key pair as the panel presents it: where its files are, and what its public key says.
///
/// The parse outcome is a `Result` rather than an optional, so "this entry's public key is
/// not readable" is an explicit state carrying its reason instead of an absence that could
/// mean anything. An entry is never dropped for failing to parse.
///
/// The presentation projections live here rather than in a view, following
/// `SSHDirectoryStatus.displayPath`: a view that has to compute what to show is a view that
/// cannot be reasoned about without reading it.
nonisolated struct SSHKeyPair: Equatable, Sendable, Identifiable {

    let location: SSHKeyPairLocation
    let publicKey: Result<SSHPublicKey, SSHPublicKeyError>

    /// The name is unique within one directory because it comes from a file name, which is
    /// what lets a deletion act on exactly the entry the user selected.
    var id: SSHKeyName { location.name }

    init(location: SSHKeyPairLocation, publicKey: Result<SSHPublicKey, SSHPublicKeyError>) {
        self.location = location
        self.publicKey = publicKey
    }

    var displayName: String { location.name.rawValue }

    /// The parsed public key, or `nil` where it could not be parsed.
    var parsedPublicKey: SSHPublicKey? {
        try? publicKey.get()
    }

    /// Why the public key could not be parsed, or `nil` where it could.
    var parseFailure: SSHPublicKeyError? {
        guard case .failure(let error) = publicKey else { return nil }
        return error
    }

    /// Whether the public key exists without its private half.
    var isPrivateKeyMissing: Bool {
        location.privateKeyURL == nil
    }

    var hasCertificate: Bool {
        location.certificateURL != nil
    }
}
