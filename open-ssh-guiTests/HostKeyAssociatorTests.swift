import Foundation
import Testing

/// Which key each host uses, and which keys are shared. The warning is only useful if it is
/// right: it must see through different spellings of one key, and must not fire for policy
/// blocks or for a host declared twice.
@Suite("Host key associator")
nonisolated struct HostKeyAssociatorTests {

    private static let home = URL(filePath: "/fabricated/home")
    private static let keys = URL(filePath: "/fabricated/keys")
    private static let config = keys.appending(path: "config")

    private static let context = IdentityResolutionContext(
        homeDirectory: home,
        sshDirectory: SSHDirectory(url: keys),
        userName: "alice",
        defaultDirectory: home.appending(path: SSHDirectoryResolver.directoryName)
    )

    private static func pair(_ name: String, privateKey: Bool = true) -> SSHKeyPair {
        let key = SSHKeyName.discovered(name)!
        return SSHKeyPair(
            location: SSHKeyPairLocation(
                name: key,
                publicKeyURL: key.publicKeyURL(in: keys),
                privateKeyURL: privateKey ? key.privateKeyURL(in: keys) : nil,
                certificateURL: nil
            ),
            publicKey: .failure(.fileUnreadable)
        )
    }

    private static func configuration(_ text: String) -> SSHConfiguration {
        let parsed = SSHConfigParser().parse(Data(text.utf8), at: config, inclusionChain: [], writability: .writable)
        return SSHConfiguration(files: [parsed.file], entries: parsed.entries, issues: [], includePatterns: [])
    }

    private static func index(_ text: String, pairs: [SSHKeyPair] = [pair("id_work"), pair("id_home")]) -> (HostKeyIndex, [HostEntry]) {
        let configuration = configuration(text)
        return (HostKeyAssociator().index(configuration, pairs: pairs, context: context), configuration.entries)
    }

    private static func name(_ raw: String) -> SSHKeyName { SSHKeyName.discovered(raw)! }

    // MARK: - 2.3–2.7 associations

    @Test("Each IdentityFile is associated in order, by what it resolves to")
    func associations() throws {
        let (index, entries) = Self.index(
            """
            Host a
                IdentityFile /fabricated/keys/id_work
                IdentityFile /fabricated/keys/missing
                IdentityFile ~/keys/%h
                IdentityFile none
            Host b
            """
        )

        #expect(index.associations(for: entries[0].id) == [
            .listed(Self.name("id_work")),
            .unlisted(raw: "/fabricated/keys/missing"),
            .unresolved(raw: "~/keys/%h", .connectionToken("%h")),
            .disabled,
        ])
        // No IdentityFile at all is OpenSSH's default identities, which presentation says.
        #expect(index.associations(for: entries[1].id).isEmpty)
        #expect(index.hasUnresolvedReferences)
    }

    @Test("A reference to the public key names the same pair")
    func publicKeyReference() {
        let (index, entries) = Self.index("Host a\n    IdentityFile /fabricated/keys/id_work.pub\n")
        #expect(index.associations(for: entries[0].id) == [.listed(Self.name("id_work"))])
    }

    @Test("A pair with no private key is still matched through its public key")
    func pairWithoutPrivateKey() {
        let (index, entries) = Self.index(
            "Host a\n    IdentityFile /fabricated/keys/orphan.pub\n",
            pairs: [Self.pair("orphan", privateKey: false)]
        )
        #expect(index.associations(for: entries[0].id) == [.listed(Self.name("orphan"))])
    }

    // MARK: - 3.1–3.3 / 3.8 sharing

    @Test("Differently spelled references to one key are the same key, and both hosts are warned")
    func differentSpellingsAreShared() {
        let (index, entries) = Self.index(
            """
            Host a
                IdentityFile /fabricated/keys/id_work
            Host b
                IdentityFile /fabricated/keys/./sub/../id_work.pub
            Host c
                IdentityFile /fabricated/keys/id_home
            """
        )

        #expect(index.sharingHosts(for: entries[0].id) == ["b"])
        #expect(index.sharingHosts(for: entries[1].id) == ["a"])
        #expect(index.sharingHosts(for: entries[2].id).isEmpty)
    }

    @Test("A pattern entry naming a key neither warns nor is counted")
    func patternEntriesAreExcluded() {
        let (index, entries) = Self.index(
            """
            Host *
                IdentityFile /fabricated/keys/id_work
            Host a
                IdentityFile /fabricated/keys/id_work
            """
        )

        #expect(index.sharingHosts(for: entries[0].id).isEmpty)
        #expect(index.sharingHosts(for: entries[1].id).isEmpty)
        #expect(index.hosts(using: Self.name("id_work"), excluding: nil) == ["a"])
    }

    @Test("A host declared twice with the same patterns is not sharing a key with itself")
    func duplicatePatternSetIsOneHost() {
        let (index, entries) = Self.index(
            """
            Host github.com
                IdentityFile /fabricated/keys/id_work
            Host GitHub.com
                IdentityFile /fabricated/keys/id_work
            """
        )

        #expect(index.sharingHosts(for: entries[0].id).isEmpty)
        #expect(index.sharingHosts(for: entries[1].id).isEmpty)
    }

    @Test("The warning disappears once only one host uses the key")
    func warningDisappears() {
        let shared = Self.index(
            "Host a\n    IdentityFile /fabricated/keys/id_work\nHost b\n    IdentityFile /fabricated/keys/id_work\n"
        )
        #expect(shared.0.sharingHosts(for: shared.1[0].id) == ["b"])

        let alone = Self.index(
            "Host a\n    IdentityFile /fabricated/keys/id_work\nHost b\n    IdentityFile /fabricated/keys/id_home\n"
        )
        #expect(alone.0.sharingHosts(for: alone.1[0].id).isEmpty)
    }

    // MARK: - 4.3 / 11 queries

    @Test("Hosts using a key can leave out the one being edited")
    func hostsUsingAKey() {
        let (index, entries) = Self.index(
            "Host a\n    IdentityFile /fabricated/keys/id_work\nHost b\n    IdentityFile /fabricated/keys/id_work\n"
        )

        #expect(index.hosts(using: Self.name("id_work"), excluding: nil) == ["a", "b"])
        #expect(index.hosts(using: Self.name("id_work"), excluding: entries[0].id) == ["b"])
        #expect(index.hosts(using: Self.name("id_home"), excluding: nil).isEmpty)
    }

    @Test("Entries referencing a file include pattern entries, which a rename would break too")
    func entriesReferencingAFile() {
        let (index, entries) = Self.index(
            "Host *\n    IdentityFile /fabricated/keys/id_work\nHost a\n    IdentityFile /fabricated/keys/id_home\n"
        )

        #expect(index.entries(referencing: Self.keys.appending(path: "id_work")) == [entries[0].id])
        #expect(index.entries(referencing: Self.keys.appending(path: "nothing")).isEmpty)
        #expect(!index.hasUnresolvedReferences)
    }
}
