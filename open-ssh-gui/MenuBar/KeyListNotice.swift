import Foundation

/// The outcome of the last thing the user asked for.
///
/// A closed set, so every outcome the panel can report is visible in one place and each
/// carries only what its message needs. `leftIncomplete` is separate from `failed` because
/// the two mean different things to the user: one says nothing happened, the other says the
/// directory is not as it was and names what is where.
nonisolated enum KeyListNotice: Sendable, Equatable {
    case copied(SSHKeyName)
    case renamed(SSHKeyName)
    case deleted(SSHKeyName)
    case generated(SSHKeyName)

    /// The operation did not happen, and nothing changed.
    case failed(reason: String)

    /// The operation did not complete, and the directory is mid-change. The reason names
    /// what is still where.
    case leftIncomplete(reason: String)

    var message: String {
        switch self {
        case .copied(let name):
            "Copied \(name.rawValue).pub to the clipboard."
        case .renamed(let name):
            "Renamed to \(name.rawValue)."
        case .deleted(let name):
            "Deleted \(name.rawValue)."
        case .generated(let name):
            "Created \(name.rawValue)."
        case .failed(let reason), .leftIncomplete(let reason):
            reason
        }
    }

    /// The status vocabulary the design system's indicator renders, so the view decides
    /// nothing about how an outcome looks.
    var role: StatusRole {
        switch self {
        case .copied, .renamed, .deleted, .generated: .success
        case .failed: .failure
        case .leftIncomplete: .warning
        }
    }
}
