import Foundation

/// The configuration change in flight, if any.
///
/// There is no case for two. A second edit, creation or deletion has nowhere to be recorded,
/// so the model refuses it by construction — the same mechanism `KeyOperation` uses.
nonisolated enum ConfigOperation: Sendable, Equatable {
    case idle
    case creating
    case updating(HostEntryID)
    case deleting(HostEntryID)

    var isInFlight: Bool { self != .idle }

    /// The entry being changed, so its row can show its own progress.
    var entry: HostEntryID? {
        switch self {
        case .idle, .creating: nil
        case .updating(let entry), .deleting(let entry): entry
        }
    }
}
