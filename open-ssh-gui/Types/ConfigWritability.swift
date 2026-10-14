import Foundation

/// Whether the app may change a configuration file.
///
/// A closed pair rather than a `Bool`, so a read-only file always says why.
nonisolated enum ConfigWritability: Sendable, Equatable {
    case writable
    case readOnly(ConfigReadOnlyReason)

    var isWritable: Bool { self == .writable }

    /// Why the file cannot be changed, or `nil` where it can.
    var readOnlyReason: String? {
        guard case .readOnly(let reason) = self else { return nil }
        return reason.reason
    }
}
