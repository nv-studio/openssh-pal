import Foundation

/// One row of the host form's key picker.
nonisolated struct HostKeyChoiceOption: Identifiable, Sendable, Equatable {
    let choice: HostKeyChoice
    let title: String

    /// A second line: the key's type, what "no key" means, or the values being kept.
    let detail: String?

    /// `false` for a pair whose private key is missing: `IdentityFile` would name a file that
    /// is not there.
    let isAvailable: Bool

    /// Other concrete hosts already using this key. Empty means no warning.
    let sharingHosts: [String]

    var id: HostKeyChoice { choice }

    var isShared: Bool { !sharingHosts.isEmpty }

    /// The warning symbol for a key other hosts use, as in the host list; otherwise a key, or a
    /// crossed-out key for one that cannot be chosen.
    var symbolName: String {
        if isShared { return StatusRole.warning.symbolName }
        return isAvailable ? "key" : "key.slash"
    }

    var symbolColor: ColorRole {
        isShared ? .warning : .secondaryText
    }

    /// Shown under the title when the key is shared.
    var sharingText: String? {
        isShared ? "Used by \(sharingHosts.joined(separator: ", "))" : nil
    }

    var accessibilityLabel: String {
        var parts = [title]
        if let detail { parts.append(detail) }
        if !isAvailable { parts.append("Unavailable") }
        if let sharingText { parts.append("Warning: \(sharingText)") }
        return parts.joined(separator: ". ")
    }
}
