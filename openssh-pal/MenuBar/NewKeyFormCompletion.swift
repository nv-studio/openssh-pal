import Foundation

/// How the create form finished.
///
/// A closed pair, so "finished, but neither created nor cancelled" cannot be represented.
/// The panel reads this to go back to the list, and the list reads the created pair from it —
/// which is also what lets a generation that outlived a panel dismissal be presented the next
/// time the panel opens.
nonisolated enum NewKeyFormCompletion: Sendable, Equatable {
    case cancelled
    case created(SSHKeyPair)

    var createdPair: SSHKeyPair? {
        guard case .created(let pair) = self else { return nil }
        return pair
    }
}
