import Foundation

/// What `backUpIfAbsent` did.
///
/// An existing backup is never replaced: the first one is the copy from before the app ever
/// touched the file, which is the one worth restoring.
nonisolated enum BackupOutcome: Sendable, Equatable {
    case created
    case alreadyPresent
}
