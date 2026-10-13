import Foundation

/// Where a key pair's files are, before any of them has been read.
///
/// This is the whole output of discovery, which is a pure function over a directory listing.
/// Keeping it separate from `SSHKeyPair` is what lets the pairing rules be tested without a
/// single file read.
///
/// The public key's location is not optional: a pair is discovered *from* its public key, so
/// one always exists. The private key's is, because a public key whose private half was
/// deleted is still worth presenting.
nonisolated struct SSHKeyPairLocation: Equatable, Sendable {
    let name: SSHKeyName
    let publicKeyURL: URL
    let privateKeyURL: URL?
    let certificateURL: URL?

    init(name: SSHKeyName, publicKeyURL: URL, privateKeyURL: URL?, certificateURL: URL?) {
        self.name = name
        self.publicKeyURL = publicKeyURL
        self.privateKeyURL = privateKeyURL
        self.certificateURL = certificateURL
    }

    /// The directory all of this pair's files live in.
    var directory: URL {
        publicKeyURL.deletingLastPathComponent()
    }

    /// Every file that belongs to this pair, in the order an operation should touch them.
    ///
    /// The private key comes first so that a half-finished rename or deletion leaves the
    /// public key — the half the app can still identify the pair from — rather than
    /// orphaning the private one.
    var files: [URL] {
        [privateKeyURL, publicKeyURL, certificateURL].compactMap(\.self)
    }
}
