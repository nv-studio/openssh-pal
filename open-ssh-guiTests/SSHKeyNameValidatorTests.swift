import Foundation
import Testing

/// Every case is driven from a fabricated directory listing. The validator performs no
/// file-system access of its own, which is what lets the collision rule be exercised here
/// without a single real file.
@Suite("Key name validation against a directory")
nonisolated struct SSHKeyNameValidatorTests {

    private static let directory = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)

    private static func entry(_ name: String) -> URL {
        directory.appending(path: name)
    }

    private static func name(_ raw: String) throws -> SSHKeyName {
        try SSHKeyName.validated(raw).get()
    }

    private static func validate(
        _ proposed: String,
        entries: [String],
        replacing current: SSHKeyName? = nil
    ) -> Result<SSHKeyName, SSHKeyNameError> {
        SSHKeyNameValidator().validate(
            proposed,
            in: directory,
            against: entries.map(entry),
            replacing: current
        )
    }

    // MARK: - the shape rules are the same rules, applied by one implementation

    @Test("The shape rules reach the caller through the validator, so rename and create agree")
    func shapeRulesAreAppliedByTheValidator() throws {
        #expect(Self.validate("", entries: []) == .failure(.empty))
        #expect(Self.validate("a/b", entries: []) == .failure(.notAPlainFileName("a/b")))
        #expect(Self.validate("k.pub", entries: []) == .failure(.endsInPublicKeyExtension("k.pub")))
        #expect(Self.validate("config", entries: []) == .failure(.reservedByOpenSSH("config")))
    }

    @Test("A name no rule rejects is accepted against an empty directory")
    func acceptableNameIsAccepted() throws {
        let accepted = try Self.validate("work_key", entries: []).get()

        #expect(accepted.rawValue == "work_key")
    }

    // MARK: - 5.5 collision against every file the operation writes

    @Test("A name whose private key file already exists is rejected, naming that file")
    func collisionOnThePrivateKeyFile() {
        let outcome = Self.validate("work_key", entries: ["work_key"])

        #expect(outcome == .failure(.wouldReplace(Self.entry("work_key"))))
    }

    @Test("A collision on the public key file is caught, not only on the private key file")
    func collisionOnThePublicKeyFile() {
        let outcome = Self.validate("work_key", entries: ["work_key.pub"])

        #expect(outcome == .failure(.wouldReplace(Self.entry("work_key.pub"))))
    }

    @Test("A collision on the certificate file is caught, so a rename cannot adopt a stranger's certificate")
    func collisionOnTheCertificateFile() {
        let outcome = Self.validate("work_key", entries: ["work_key-cert.pub"])

        #expect(outcome == .failure(.wouldReplace(Self.entry("work_key-cert.pub"))))
    }

    @Test("A directory full of other keys does not collide")
    func unrelatedEntriesDoNotCollide() throws {
        let accepted = try Self.validate(
            "work_key",
            entries: ["id_ed25519", "id_ed25519.pub", "config", "known_hosts", "other-cert.pub"]
        ).get()

        #expect(accepted.rawValue == "work_key")
    }

    // MARK: - 5.5 a rename that keeps its own name

    @Test("A rename that keeps the pair's current name is not reported as colliding with itself")
    func keepingTheCurrentNameIsNotASelfCollision() throws {
        let current = try Self.name("work_key")

        let accepted = try Self.validate(
            "work_key",
            entries: ["work_key", "work_key.pub", "work_key-cert.pub"],
            replacing: current
        ).get()

        #expect(accepted == current)
    }

    @Test("A rename still collides with a different pair's files")
    func renameStillCollidesWithAnotherPair() throws {
        let current = try Self.name("work_key")

        let outcome = Self.validate(
            "other_key",
            entries: ["work_key", "work_key.pub", "other_key.pub"],
            replacing: current
        )

        #expect(outcome == .failure(.wouldReplace(Self.entry("other_key.pub"))))
    }

    // MARK: - no file-system access

    @Test("Validation reads nothing: an entry list naming files that do not exist is enough")
    func validationTouchesNoFile() throws {
        // The entries below name nothing real. That the collision is still reported proves
        // the rule runs entirely from the supplied listing.
        let outcome = Self.validate("work_key", entries: ["work_key"])

        #expect(outcome == .failure(.wouldReplace(Self.entry("work_key"))))
    }

    @Test("A listing from a subdirectory cannot be mistaken for an entry of this directory")
    func entriesFromElsewhereDoNotCollide() throws {
        let elsewhere = URL(filePath: "/fabricated/other/work_key")

        let accepted = try SSHKeyNameValidator().validate(
            "work_key",
            in: Self.directory,
            against: [elsewhere],
            replacing: nil
        ).get()

        #expect(accepted.rawValue == "work_key")
    }
}
