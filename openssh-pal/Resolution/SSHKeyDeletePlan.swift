import Foundation

/// The ordered removals a deletion performs.
///
/// Pure, and derived from one pair's own locations. There is no listing, no pattern and no
/// directory scan here, so a file the user did not identify through a presented entry has no
/// path into the plan — which is how "never delete a bystander" is a property of the type
/// rather than a check someone has to remember.
nonisolated struct SSHKeyDeletePlan {

    /// The files to remove, in the order they should go.
    ///
    /// The private key goes first, so a deletion that stops partway leaves the public key —
    /// the half the panel can still list — rather than an unusable private key with nothing
    /// to identify it.
    let removals: [URL]

    init(location: SSHKeyPairLocation) {
        removals = location.files
    }

    /// Convenience over the pair the presentation holds.
    init(pair: SSHKeyPair) {
        self.init(location: pair.location)
    }
}
