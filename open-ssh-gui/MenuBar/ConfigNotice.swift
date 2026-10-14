import Foundation

/// The outcome of the last configuration change the user asked for.
nonisolated enum ConfigNotice: Sendable, Equatable {
    case created(String)
    case updated(String)
    case deleted(String)

    /// The file changed since the form read it, so nothing was written and the list re-read.
    case changedOnDisk(fileName: String)

    /// Nothing changed, for the reason given.
    case failed(reason: String)

    var message: String {
        switch self {
        case .created(let host): "Added Host \(host)."
        case .updated(let host): "Saved Host \(host)."
        case .deleted(let host): "Deleted Host \(host)."
        case .changedOnDisk(let fileName):
            "\(fileName) changed since it was opened, so nothing was written. The hosts were read again."
        case .failed(let reason): reason
        }
    }

    var role: StatusRole {
        switch self {
        case .created, .updated, .deleted: .success
        case .changedOnDisk: .warning
        case .failed: .failure
        }
    }
}
