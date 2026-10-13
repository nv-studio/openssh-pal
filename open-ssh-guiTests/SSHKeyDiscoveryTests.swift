import Foundation
import Testing

/// Every case is driven from a fabricated listing. The discovery rules perform no
/// file-system access at all, which is what lets the whole of them be exercised from an
/// array of URLs.
@Suite("Key pair discovery from a directory listing")
nonisolated struct SSHKeyDiscoveryTests {

    private static let directory = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)
    private static let discovery = SSHKeyDiscovery()

    private static func file(_ name: String) -> URL {
        directory.appending(path: name)
    }

    private static func subdirectory(_ name: String) -> URL {
        directory.appending(path: name, directoryHint: .isDirectory)
    }

    private static func locations(_ entries: [URL]) -> [SSHKeyPairLocation] {
        discovery.pairLocations(in: entries)
    }

    private static func names(_ entries: [URL]) -> [String] {
        locations(entries).map(\.name.rawValue)
    }

    // MARK: - 1.2 pairing

    @Test("A public key and its sibling make one pair")
    func publicKeyPairsWithItsPrivateSibling() throws {
        let locations = Self.locations([Self.file("id_ed25519"), Self.file("id_ed25519.pub")])

        #expect(locations.count == 1)
        let pair = try #require(locations.first)
        #expect(pair.name.rawValue == "id_ed25519")
        #expect(pair.publicKeyURL == Self.file("id_ed25519.pub"))
        #expect(pair.privateKeyURL == Self.file("id_ed25519"))
        #expect(pair.certificateURL == nil)
    }

    @Test("Discovery runs from the public key, so a private key alone is not an entry")
    func privateKeyAloneIsNotAnEntry() {
        // Accepted consequence of discovering from `*.pub`: a pair whose public key was
        // deleted is invisible. Recovering it means `ssh-keygen -y`, which this app does not
        // offer.
        #expect(Self.names([Self.file("id_ed25519")]).isEmpty)
    }

    // MARK: - 1.3 an absent private key

    @Test("A public key with no sibling is still an entry, with its private key reported absent")
    func absentPrivateKeyIsReported() throws {
        let pair = try #require(Self.locations([Self.file("orphan.pub")]).first)

        #expect(pair.name.rawValue == "orphan")
        #expect(pair.privateKeyURL == nil)
    }

    // MARK: - 1.4 exclusions

    @Test("The files OpenSSH owns are never entries")
    func openSSHOwnFilesAreExcluded() {
        let entries = [
            Self.file("config"),
            Self.file("known_hosts"),
            Self.file("known_hosts.old"),
            Self.file("authorized_keys"),
        ]

        #expect(Self.names(entries).isEmpty)
    }

    @Test("A reserved name is excluded even where a public key file would pair with it")
    func reservedNameIsExcludedEvenWithAPublicKey() {
        // `config.pub` would otherwise produce a pair whose "private key" is the user's SSH
        // configuration file — which a deletion would then remove.
        let entries = [Self.file("config"), Self.file("config.pub")]

        #expect(Self.names(entries).isEmpty)
    }

    @Test("A directory is never an entry, whatever it is called")
    func directoriesAreExcluded() {
        let entries = [
            Self.subdirectory("nested"),
            Self.subdirectory("looks_like.pub"),
        ]

        #expect(Self.names(entries).isEmpty)
    }

    @Test("A directory is not mistaken for a pair's private key either")
    func aDirectoryIsNotAPrivateKey() throws {
        let entries = [Self.subdirectory("id_ed25519"), Self.file("id_ed25519.pub")]

        let pair = try #require(Self.locations(entries).first)

        #expect(pair.privateKeyURL == nil)
    }

    // MARK: - 1.5 certificates

    @Test("A certificate attaches to the pair whose name it extends rather than listing itself")
    func certificateAttachesToItsPair() throws {
        let entries = [
            Self.file("id_ed25519"),
            Self.file("id_ed25519.pub"),
            Self.file("id_ed25519-cert.pub"),
        ]

        let locations = Self.locations(entries)

        #expect(locations.count == 1)
        let pair = try #require(locations.first)
        #expect(pair.name.rawValue == "id_ed25519")
        #expect(pair.certificateURL == Self.file("id_ed25519-cert.pub"))
    }

    @Test("A certificate with no pair to attach to is not an entry of its own")
    func orphanCertificateIsNotAnEntry() {
        #expect(Self.names([Self.file("stranger-cert.pub")]).isEmpty)
    }

    @Test("A key whose own name ends in -cert is not mistaken for a certificate")
    func aKeyNamedCertIsStillAKey() throws {
        // `work-cert.pub` is a certificate for `work`. A key pair genuinely named
        // `work-cert` would have to be spelled `work-cert` plus `work-cert.pub`, which is
        // the same file name — so the certificate rule wins, and that is the rule `ssh(1)`
        // itself applies.
        let entries = [Self.file("work"), Self.file("work.pub"), Self.file("work-cert.pub")]

        let locations = Self.locations(entries)

        #expect(locations.map(\.name.rawValue) == ["work"])
        #expect(try #require(locations.first).certificateURL == Self.file("work-cert.pub"))
    }

    // MARK: - ordering

    @Test("Entries are ordered by name, so the presented list is stable across refreshes")
    func entriesAreOrderedByName() {
        let entries = [
            Self.file("work.pub"),
            Self.file("alpha.pub"),
            Self.file("beta.pub"),
        ]

        #expect(Self.names(entries) == ["alpha", "beta", "work"])
        // The same listing in another order yields the same presentation.
        #expect(Self.names(entries.reversed()) == ["alpha", "beta", "work"])
    }

    // MARK: - oddities that must not produce an entry or a trap

    @Test("A file named only for the extension is not an entry")
    func bareExtensionIsNotAnEntry() {
        #expect(Self.names([Self.file(".pub")]).isEmpty)
        #expect(Self.names([Self.file("-cert.pub")]).isEmpty)
    }

    @Test("A file with no extension at all is not an entry")
    func extensionlessFileIsNotAnEntry() {
        #expect(Self.names([Self.file("notes")]).isEmpty)
    }

    @Test("An empty listing yields no entries rather than failing")
    func emptyListingYieldsNothing() {
        #expect(Self.locations([]).isEmpty)
    }

    // MARK: - 14.6 nothing is read

    @Test("A listing naming files that do not exist still produces the pairs it describes")
    func discoveryReadsNothing() throws {
        // None of these paths exist. That the pairs come back anyway is the assertion: the
        // rule runs entirely from the supplied values.
        let entries = [
            Self.file("a"), Self.file("a.pub"), Self.file("a-cert.pub"),
            Self.file("b.pub"),
        ]

        let locations = Self.locations(entries)

        #expect(locations.map(\.name.rawValue) == ["a", "b"])
        #expect(locations[0].files.count == 3)
        #expect(locations[1].files == [Self.file("b.pub")])
    }

    @Test("Every derived location stays inside the directory the entries came from")
    func derivedLocationsStayInsideTheDirectory() {
        let entries = [Self.file("a"), Self.file("a.pub"), Self.file("a-cert.pub")]

        for location in Self.locations(entries) {
            for file in location.files {
                #expect(file.deletingLastPathComponent().standardizedFileURL
                    == Self.directory.standardizedFileURL)
            }
        }
    }
}
