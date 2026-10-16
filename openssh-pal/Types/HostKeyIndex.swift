import Foundation

/// Which key each host uses, and which keys are shared between hosts.
///
/// Built by `HostKeyAssociator` and queried by presentation. Only *concrete* hosts take part in
/// sharing: a `Host *` block naming a key describes a policy, and counting it would flag every
/// host that also names that key.
nonisolated struct HostKeyIndex: Sendable, Equatable {

    /// One concrete host using a key.
    nonisolated struct Use: Sendable, Equatable {
        let entry: HostEntryID
        let identity: Set<String>
        let displayName: String
    }

    private let associationsByEntry: [HostEntryID: [KeyAssociation]]
    private let resolvedPathsByEntry: [HostEntryID: [String]]
    private let identityByEntry: [HostEntryID: Set<String>]
    private let concreteEntries: Set<HostEntryID>

    /// The concrete hosts using each key, in load order.
    private let usesByKey: [SSHKeyName: [Use]]

    /// Whether any `IdentityFile` could not be resolved, which might hide a reference.
    let hasUnresolvedReferences: Bool

    init(
        associationsByEntry: [HostEntryID: [KeyAssociation]],
        resolvedPathsByEntry: [HostEntryID: [String]],
        identityByEntry: [HostEntryID: Set<String>],
        concreteEntries: Set<HostEntryID>,
        usesByKey: [SSHKeyName: [Use]],
        hasUnresolvedReferences: Bool
    ) {
        self.associationsByEntry = associationsByEntry
        self.resolvedPathsByEntry = resolvedPathsByEntry
        self.identityByEntry = identityByEntry
        self.concreteEntries = concreteEntries
        self.usesByKey = usesByKey
        self.hasUnresolvedReferences = hasUnresolvedReferences
    }

    /// An index with nothing in it, for a configuration that has not loaded.
    static let empty = HostKeyIndex(
        associationsByEntry: [:],
        resolvedPathsByEntry: [:],
        identityByEntry: [:],
        concreteEntries: [],
        usesByKey: [:],
        hasUnresolvedReferences: false
    )

    /// One association per `IdentityFile`, in order. Empty means OpenSSH's default identities.
    func associations(for entry: HostEntryID) -> [KeyAssociation] {
        associationsByEntry[entry] ?? []
    }

    /// The other concrete hosts sharing a key with this one. Empty means no warning — and is
    /// always empty for a pattern entry.
    func sharingHosts(for entry: HostEntryID) -> [String] {
        guard concreteEntries.contains(entry), let identity = identityByEntry[entry] else { return [] }

        var names: [String] = []
        for case .listed(let key) in associations(for: entry) {
            for use in usesByKey[key] ?? [] where use.identity != identity && !names.contains(use.displayName) {
                names.append(use.displayName)
            }
        }
        return names
    }

    /// The concrete hosts using `key`, leaving out the host `entry` is — the one being edited.
    func hosts(using key: SSHKeyName, excluding entry: HostEntryID?) -> [String] {
        let excluded = entry.flatMap { identityByEntry[$0] }
        var names: [String] = []
        for use in usesByKey[key] ?? [] where use.identity != excluded && !names.contains(use.displayName) {
            names.append(use.displayName)
        }
        return names
    }

    /// Every entry, concrete or not, with an `IdentityFile` resolving to `url`.
    func entries(referencing url: URL) -> [HostEntryID] {
        let path = IdentityResolutionContext.normalizedPath(of: url)
        return resolvedPathsByEntry
            .filter { $0.value.contains(path) }
            .map(\.key)
    }
}
