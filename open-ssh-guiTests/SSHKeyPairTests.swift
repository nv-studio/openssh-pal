import Foundation
import Testing

@Suite("Key pairs and their parsed public keys")
struct SSHKeyPairTests {

    private static let directory = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)

    private static func name(_ raw: String) throws -> SSHKeyName {
        try SSHKeyName.validated(raw).get()
    }

    private static func location(
        _ raw: String,
        privateKey: Bool = true,
        certificate: Bool = false
    ) throws -> SSHKeyPairLocation {
        let name = try name(raw)
        return SSHKeyPairLocation(
            name: name,
            publicKeyURL: name.publicKeyURL(in: directory),
            privateKeyURL: privateKey ? name.privateKeyURL(in: directory) : nil,
            certificateURL: certificate ? name.certificateURL(in: directory) : nil
        )
    }

    private static let parsed = SSHPublicKey(
        algorithm: .ed25519,
        bitLength: 256,
        fingerprint: SSHFingerprint(value: "SHA256:abc"),
        comment: "user@host"
    )

    // MARK: - an absent private key is data, not an error

    @Test("A pair whose private key is absent is representable, and says so")
    func absentPrivateKeyIsData() throws {
        let pair = SSHKeyPair(location: try Self.location("orphan", privateKey: false), publicKey: .success(Self.parsed))

        #expect(pair.isPrivateKeyMissing)
        #expect(pair.location.privateKeyURL == nil)
    }

    @Test("A pair holding both files does not report a missing private key")
    func completePairIsNotMissingAnything() throws {
        let pair = SSHKeyPair(location: try Self.location("work"), publicKey: .success(Self.parsed))

        #expect(!pair.isPrivateKeyMissing)
    }

    // MARK: - an unreadable public key is a state on the entry

    @Test("A pair whose public key failed to parse is representable without an optional standing in")
    func unparseablePublicKeyIsAState() throws {
        let pair = SSHKeyPair(location: try Self.location("broken"), publicKey: .failure(.malformedLine))

        #expect(pair.parsedPublicKey == nil)
        #expect(pair.parseFailure == .malformedLine)
        // The entry survives: it still knows its own name and where its files are.
        #expect(pair.displayName == "broken")
    }

    @Test("A pair that parsed exposes its attributes and no failure")
    func parsedPairExposesItsAttributes() throws {
        let pair = SSHKeyPair(location: try Self.location("work"), publicKey: .success(Self.parsed))

        #expect(pair.parsedPublicKey == Self.parsed)
        #expect(pair.parseFailure == nil)
    }

    // MARK: - certificates

    @Test("A pair carrying a certificate indicates it")
    func certificateIsIndicated() throws {
        let withCertificate = SSHKeyPair(
            location: try Self.location("work", certificate: true),
            publicKey: .success(Self.parsed)
        )
        let without = SSHKeyPair(location: try Self.location("work"), publicKey: .success(Self.parsed))

        #expect(withCertificate.hasCertificate)
        #expect(!without.hasCertificate)
    }

    // MARK: - identity

    @Test("A pair is identified by its name, which is unique within one directory")
    func identityIsTheName() throws {
        let pair = SSHKeyPair(location: try Self.location("work"), publicKey: .success(Self.parsed))
        let name = try Self.name("work")

        #expect(pair.id == name)
    }

    // MARK: - comments

    @Test("An absent comment stays distinguishable from an empty one")
    func absentCommentDiffersFromEmpty() {
        let absent = SSHPublicKey(algorithm: .ed25519, bitLength: 256, fingerprint: SSHFingerprint(value: "SHA256:a"), comment: nil)
        let empty = SSHPublicKey(algorithm: .ed25519, bitLength: 256, fingerprint: SSHFingerprint(value: "SHA256:a"), comment: "")

        #expect(absent.comment == nil)
        #expect(empty.comment == "")
        #expect(absent != empty)
    }

    // MARK: - a size that could not be derived

    @Test("A key whose size could not be derived marks it unavailable rather than guessing")
    func undeterminableSizeIsMarkedUnavailable() {
        let key = SSHPublicKey(
            algorithm: .other("sk-ssh-ed25519@openssh.com"),
            bitLength: nil,
            fingerprint: SSHFingerprint(value: "SHA256:a"),
            comment: nil
        )

        #expect(key.bitLength == nil)
    }
}

@Suite("Public key algorithms")
struct SSHKeyAlgorithmTests {

    @Test("Every algorithm this app names round-trips through its wire name")
    func wireNamesRoundTrip() {
        let known: [SSHKeyAlgorithm] = [
            .ed25519, .rsa, .dsa,
            .ecdsa(.nistp256), .ecdsa(.nistp384), .ecdsa(.nistp521),
        ]

        for algorithm in known {
            #expect(SSHKeyAlgorithm(wireName: algorithm.wireName) == algorithm)
        }
    }

    @Test("The wire names are OpenSSH's own spellings, since they come out of the key blob")
    func wireNamesAreOpenSSHSpellings() {
        #expect(SSHKeyAlgorithm.ed25519.wireName == "ssh-ed25519")
        #expect(SSHKeyAlgorithm.rsa.wireName == "ssh-rsa")
        #expect(SSHKeyAlgorithm.dsa.wireName == "ssh-dss")
        #expect(SSHKeyAlgorithm.ecdsa(.nistp256).wireName == "ecdsa-sha2-nistp256")
        #expect(SSHKeyAlgorithm.ecdsa(.nistp521).wireName == "ecdsa-sha2-nistp521")
    }

    @Test("Every algorithm names itself for presentation, falling back to the wire name")
    func everyAlgorithmNamesItself() {
        #expect(SSHKeyAlgorithm.ed25519.displayName == "Ed25519")
        #expect(SSHKeyAlgorithm.rsa.displayName == "RSA")
        #expect(SSHKeyAlgorithm.dsa.displayName == "DSA")
        #expect(SSHKeyAlgorithm.ecdsa(.nistp384).displayName == "ECDSA nistp384")
        #expect(SSHKeyAlgorithm.other("sk-ssh-ed25519@openssh.com").displayName == "sk-ssh-ed25519@openssh.com")
    }

    @Test("An algorithm this app does not know is carried rather than rejected")
    func unknownAlgorithmIsCarried() {
        let algorithm = SSHKeyAlgorithm(wireName: "sk-ssh-ed25519@openssh.com")

        #expect(algorithm == .other("sk-ssh-ed25519@openssh.com"))
        #expect(algorithm.wireName == "sk-ssh-ed25519@openssh.com")
    }

    @Test("A generated key is matched against the type that was requested")
    func algorithmMatchesARequestedType() {
        #expect(SSHKeyAlgorithm.ed25519.matches(.ed25519))
        #expect(SSHKeyAlgorithm.rsa.matches(.rsa(.bits4096)))
        #expect(SSHKeyAlgorithm.ecdsa(.nistp384).matches(.ecdsa(.nistp384)))

        #expect(!SSHKeyAlgorithm.rsa.matches(.ed25519))
        #expect(!SSHKeyAlgorithm.ecdsa(.nistp256).matches(.ecdsa(.nistp384)))
        #expect(!SSHKeyAlgorithm.other("x").matches(.ed25519))
    }
}
