import Foundation

/// Which hosts name a key, as far as the configuration can tell.
nonisolated enum HostReferenceReport: Sendable, Equatable {
    /// The configuration could not be read, so nothing is known — which is different from
    /// "no host uses this key", and must never be presented as an empty list.
    case unavailable(reason: String)

    /// The hosts whose `IdentityFile` resolves to the key, and whether some value could not be
    /// resolved and might name it too.
    case references(hosts: [String], hasUnresolved: Bool)

    /// A sentence for a rename warning or a deletion confirmation.
    var summary: String {
        switch self {
        case .unavailable(let reason):
            return "Host references could not be checked: \(reason)"
        case .references(let hosts, let hasUnresolved):
            var sentences = [
                hosts.isEmpty
                    ? "No host in the SSH configuration names this key."
                    : "Used by: \(hosts.joined(separator: ", ")).",
            ]
            if hasUnresolved {
                sentences.append("Some IdentityFile values could not be resolved and might name it too.")
            }
            return sentences.joined(separator: " ")
        }
    }
}
