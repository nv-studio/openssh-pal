import Foundation

/// Everything the app presents about a key, derived entirely from its public key file.
///
/// No private key byte is involved in producing any of this, which is what makes the
/// "never read a private key" guarantee structural rather than a rule to remember.
nonisolated struct SSHPublicKey: Equatable, Sendable {

    let algorithm: SSHKeyAlgorithm

    /// The key's size in bits, or `nil` where it could not be derived.
    ///
    /// Optional rather than a stand-in number: for an algorithm this app does not know, the
    /// size is genuinely unavailable, and the entry presents it as unavailable rather than
    /// being dropped or shown a guess.
    let bitLength: Int?

    let fingerprint: SSHFingerprint

    /// The comment field, absent when the key line carries none.
    ///
    /// `nil` and `""` are different facts — a key with no comment and a key whose comment is
    /// an empty string — so the presentation can honour "no comment" without substituting a
    /// placeholder.
    let comment: String?

    init(algorithm: SSHKeyAlgorithm, bitLength: Int?, fingerprint: SSHFingerprint, comment: String?) {
        self.algorithm = algorithm
        self.bitLength = bitLength
        self.fingerprint = fingerprint
        self.comment = comment
    }
}
