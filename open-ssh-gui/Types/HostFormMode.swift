import Foundation

/// Whether a form adds a host or changes one.
///
/// The edited entry travels with the mode, so an edit form cannot exist without the block it
/// edits.
nonisolated enum HostFormMode: Sendable, Equatable {
    case create
    case edit(HostEntry)

    var editedEntry: HostEntry? {
        guard case .edit(let entry) = self else { return nil }
        return entry
    }
}
