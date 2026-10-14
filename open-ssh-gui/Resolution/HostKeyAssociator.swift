import Foundation

/// Joins host entries to the key pairs discovery found, and works out which keys are shared.
///
/// A path matches a pair when it is the pair's private key *or* its public key, because an
/// `IdentityFile` may name a `.pub` and `ssh` then uses the matching agent key. Two references
/// are the same key when they match the same pair, however each is spelled.
///
/// Only concrete entries take part in sharing, and entries with the same patterns count as one
/// host. Recomputed whenever either input changes, so a warning disappears as soon as the last
/// other host stops using the key.
///
/// Pure.
nonisolated struct HostKeyAssociator {

    private let resolver = IdentityFileResolver()

    init() {}

    func index(_ configuration: SSHConfiguration, pairs: [SSHKeyPair], context: IdentityResolutionContext) -> HostKeyIndex {
        var keyByPath: [String: SSHKeyName] = [:]
        for pair in pairs {
            for url in [pair.location.privateKeyURL, pair.location.publicKeyURL].compactMap(\.self) {
                keyByPath[IdentityResolutionContext.normalizedPath(of: url)] = pair.id
            }
        }

        var associationsByEntry: [HostEntryID: [KeyAssociation]] = [:]
        var resolvedPathsByEntry: [HostEntryID: [String]] = [:]
        var identityByEntry: [HostEntryID: Set<String>] = [:]
        var concreteEntries: Set<HostEntryID> = []
        var usesByKey: [SSHKeyName: [HostKeyIndex.Use]] = [:]
        var hasUnresolvedReferences = false

        for entry in configuration.entries {
            identityByEntry[entry.id] = entry.hostIdentity
            if !entry.isPatternEntry { concreteEntries.insert(entry.id) }

            var associations: [KeyAssociation] = []
            var paths: [String] = []

            for declared in entry.identityFiles {
                switch resolver.resolve(declared.value, in: context).resolution {
                case .disabled:
                    associations.append(.disabled)
                case .unresolvable(let reason):
                    hasUnresolvedReferences = true
                    associations.append(.unresolved(raw: declared.value, reason))
                case .path(let url):
                    let path = IdentityResolutionContext.normalizedPath(of: url)
                    paths.append(path)
                    guard let key = keyByPath[path] else {
                        associations.append(.unlisted(raw: declared.value))
                        continue
                    }
                    associations.append(.listed(key))

                    let use = HostKeyIndex.Use(entry: entry.id, identity: entry.hostIdentity, displayName: entry.displayName)
                    if !entry.isPatternEntry, !(usesByKey[key] ?? []).contains(use) {
                        usesByKey[key, default: []].append(use)
                    }
                }
            }

            associationsByEntry[entry.id] = associations
            resolvedPathsByEntry[entry.id] = paths
        }

        return HostKeyIndex(
            associationsByEntry: associationsByEntry,
            resolvedPathsByEntry: resolvedPathsByEntry,
            identityByEntry: identityByEntry,
            concreteEntries: concreteEntries,
            usesByKey: usesByKey,
            hasUnresolvedReferences: hasUnresolvedReferences
        )
    }
}
