import Foundation

/// Which hosts use a key, for key management to warn about before a rename or deletion.
///
/// A narrow protocol so `SSHKeyListModel` depends on nothing configuration-specific, and the
/// keys and hosts models never refer to each other: `SSHConfigModel` conforms, and the
/// composition root hands it to the key list.
@MainActor
protocol HostReferenceLookup: AnyObject {
    func hostReferences(to pair: SSHKeyPair) -> HostReferenceReport
}
