import Foundation

/// The ordered moves a rename performs, and their inverse.
///
/// Pure. Separating the plan from its execution is what makes ordering, completeness and —
/// above all — rollback unit-testable without a file system, which matters because rollback
/// is the path that only runs when something has already gone wrong.
///
/// The plan decides nothing about validity: it consumes a name that has already been
/// validated against the same listing the pair came from.
nonisolated struct SSHKeyRenamePlan {

    /// One file moving from one location to another. It carries no payload, so there is no
    /// field through which a plan could express a change to a file's contents — including
    /// the comment inside the public key, which a rename must not touch.
    struct Move: Equatable, Sendable {
        let from: URL
        let to: URL
    }

    /// The moves, in the order they should be executed.
    ///
    /// The private key goes first. A rename that stops partway then leaves the public key
    /// behind — the half discovery runs from — rather than an orphaned private key the panel
    /// could not show.
    let moves: [Move]

    init(location: SSHKeyPairLocation, newName: SSHKeyName) {
        let directory = location.directory

        // Each file is paired with the destination derived for *its* role, so a pair with no
        // private key still sends its public key to the public destination. A file the pair
        // does not have contributes no step, and a destination identical to its source is
        // dropped — renaming a pair to the name it already has is a plan with no moves.
        let steps: [(source: URL?, destination: URL)] = [
            (location.privateKeyURL, newName.privateKeyURL(in: directory)),
            (location.publicKeyURL, newName.publicKeyURL(in: directory)),
            (location.certificateURL, newName.certificateURL(in: directory)),
        ]

        moves = steps.compactMap { step in
            guard let source = step.source, source != step.destination else { return nil }
            return Move(from: source, to: step.destination)
        }
    }

    /// Convenience over the pair the presentation holds.
    init(pair: SSHKeyPair, newName: SSHKeyName) {
        self.init(location: pair.location, newName: newName)
    }

    /// The moves that undo the first `count` steps of this plan.
    ///
    /// This is what a failed rename executes. It runs backwards — the most recent move is
    /// the first reversed — and `count` is clamped, so a caller that lost count cannot trap
    /// or reverse a step that never happened.
    func inverse(ofCompleted count: Int) -> [Move] {
        let completed = min(max(count, 0), moves.count)
        return moves.prefix(completed).reversed().map { Move(from: $0.to, to: $0.from) }
    }
}
