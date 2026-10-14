import Foundation

/// How a requested configuration change ended, so a form knows whether its draft still applies.
nonisolated enum ConfigMutationOutcome: Sendable, Equatable {
    /// Written.
    case completed

    /// Not written because the file changed since the draft was read. The draft no longer
    /// describes the file, so the form closes and the list is re-read.
    case changedOnDisk

    /// Not written because the write failed. The draft is still good; the notice says why.
    case failed

    /// Not attempted: another change was running, or the entry cannot be written.
    case refused
}
