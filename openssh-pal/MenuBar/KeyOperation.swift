import Foundation

/// The mutation currently in flight, if any.
///
/// There is no case for two. That is how "no second rename, deletion or creation while one
/// is in progress" is enforced rather than asserted: a second operation has nowhere to be
/// recorded, so the model refuses it by construction instead of by checking a flag someone
/// could forget to set.
nonisolated enum KeyOperation: Sendable, Equatable {
    case idle
    case renaming(SSHKeyName)
    case deleting(SSHKeyName)

    var isInFlight: Bool {
        self != .idle
    }

    /// The pair being operated on, so a row can show its own progress.
    var name: SSHKeyName? {
        switch self {
        case .idle: nil
        case .renaming(let name), .deleting(let name): name
        }
    }
}
