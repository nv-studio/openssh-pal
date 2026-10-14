import Foundation

/// Why no safe place exists for a backup.
nonisolated enum BackupLocationError: Error, Sendable, Equatable {
    /// An `Include` pattern would read a file at the backup's location, so a backup there would
    /// become a second copy of every host in it.
    case matchedByInclude(String)

    var reason: String {
        switch self {
        case .matchedByInclude(let pattern):
            "Include \(pattern) would read the backup file, so nothing was written."
        }
    }
}
