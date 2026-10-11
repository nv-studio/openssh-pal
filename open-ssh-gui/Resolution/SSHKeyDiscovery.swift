import Foundation

/// Turns a directory listing into the key pairs it describes.
///
/// Pure: the listing arrives as values and nothing here reads, probes or stats anything. That
/// is what lets every pairing and exclusion rule be exercised from an array of URLs, and it
/// is also why the rules can be stated once and trusted everywhere.
///
/// Discovery runs from `*.pub` rather than by inspecting file contents. Nothing in a file
/// name distinguishes a private key from an unrelated file, and telling them apart by content
/// would mean reading private key bytes into the app for every file in the directory on every
/// refresh. The cost is that a pair whose public key was deleted is invisible.
nonisolated struct SSHKeyDiscovery {

    init() {}

    /// The key pairs discoverable from `entries`, ordered by name.
    ///
    /// - Parameter entries: the immediate children of one directory, as the reader listed
    ///   them.
    func pairLocations(in entries: [URL]) -> [SSHKeyPairLocation] {
        // A directory is excluded by the one signal available without touching the file
        // system: `contentsOfDirectory` marks a directory URL with a trailing slash. A
        // subdirectory called `id_ed25519` must not become a pair's private key, so this
        // filter has to come before the lookup below rather than after it.
        let files = entries.filter { !$0.hasDirectoryPath }
        let byName = Dictionary(
            files.map { ($0.lastPathComponent, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return files
            .compactMap { location(ofPublicKey: $0, among: byName) }
            .sorted { $0.name < $1.name }
    }

    /// The pair `publicKey` belongs to, or `nil` where it is not a pair's public key.
    private func location(
        ofPublicKey publicKey: URL,
        among byName: [String: URL]
    ) -> SSHKeyPairLocation? {
        let fileName = publicKey.lastPathComponent

        // The certificate check comes first because `<name>-cert.pub` also ends in the
        // public key extension. A certificate is attached to its pair below, never listed.
        guard !fileName.hasSuffix(SSHKeyName.certificateSuffix) else { return nil }

        let suffix = "." + SSHKeyName.publicKeyExtension
        guard fileName.hasSuffix(suffix) else { return nil }

        let base = String(fileName.dropLast(suffix.count))

        // A file called exactly `.pub` names no pair, and a reserved name must not become
        // one: `config.pub` would otherwise produce a pair whose private key is the user's
        // SSH configuration file, which a deletion would then remove.
        guard !SSHKeyName.reservedNames.contains(base),
              let name = SSHKeyName.discovered(base)
        else { return nil }

        return SSHKeyPairLocation(
            name: name,
            publicKeyURL: publicKey,
            privateKeyURL: byName[base],
            certificateURL: byName[base + SSHKeyName.certificateSuffix]
        )
    }
}
