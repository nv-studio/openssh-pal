import Foundation
import Testing

/// The name rules that depend on nothing but the name itself. The collision rule needs a
/// directory listing and is exercised in `SSHKeyNameValidatorTests`.
@Suite("Validated key names")
struct SSHKeyNameTests {

    private static let directory = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)

    private static func rejection(_ proposed: String) throws -> SSHKeyNameError {
        let outcome = SSHKeyName.validated(proposed)
        guard case .failure(let error) = outcome else {
            throw TestFailure.unexpectedlyAccepted(proposed)
        }
        return error
    }

    private enum TestFailure: Error {
        case unexpectedlyAccepted(String)
    }

    // MARK: - 5.1 empty and whitespace

    @Test("An empty name is rejected")
    func emptyNameIsRejected() throws {
        #expect(try Self.rejection("") == .empty)
    }

    @Test("A name of nothing but whitespace is rejected, since it would name no file")
    func whitespaceOnlyNameIsRejected() throws {
        #expect(try Self.rejection("   ") == .empty)
        #expect(try Self.rejection("\t\n") == .empty)
    }

    @Test("Surrounding whitespace is trimmed rather than producing a file name with spaces")
    func surroundingWhitespaceIsTrimmed() throws {
        let name = try SSHKeyName.validated("  work_key  ").get()

        #expect(name.rawValue == "work_key")
    }

    // MARK: - 5.2 separators and traversal

    @Test("A name containing a path separator is rejected, so it cannot name another directory")
    func pathSeparatorIsRejected() throws {
        #expect(try Self.rejection("nested/key") == .notAPlainFileName("nested/key"))
        #expect(try Self.rejection("/absolute") == .notAPlainFileName("/absolute"))
    }

    @Test("A name that resolves outside the directory is rejected")
    func traversalIsRejected() throws {
        #expect(try Self.rejection("..") == .notAPlainFileName(".."))
        #expect(try Self.rejection(".") == .notAPlainFileName("."))
        #expect(try Self.rejection("../sibling") == .notAPlainFileName("../sibling"))
    }

    @Test("A name containing dots that do not traverse is accepted")
    func innocentDotsAreAccepted() throws {
        let name = try SSHKeyName.validated("id_ed25519.backup").get()

        #expect(name.rawValue == "id_ed25519.backup")
    }

    // MARK: - 5.3 public key extension

    @Test("A name ending in the public key extension is rejected, since it is added for the user")
    func publicKeyExtensionIsRejected() throws {
        #expect(try Self.rejection("mykey.pub") == .endsInPublicKeyExtension("mykey.pub"))
    }

    @Test("The public key extension is rejected whatever its case")
    func publicKeyExtensionIsRejectedCaseInsensitively() throws {
        #expect(try Self.rejection("mykey.PUB") == .endsInPublicKeyExtension("mykey.PUB"))
    }

    // MARK: - 5.4 reserved names

    @Test("Each name OpenSSH reserves is rejected as reserved")
    func reservedNamesAreRejected() throws {
        for reserved in SSHKeyName.reservedNames.sorted() {
            #expect(try Self.rejection(reserved) == .reservedByOpenSSH(reserved))
        }
    }

    @Test("The reserved set is exactly the three names OpenSSH owns in the directory")
    func reservedSetIsTheThreeOpenSSHNames() {
        #expect(SSHKeyName.reservedNames == ["config", "known_hosts", "authorized_keys"])
    }

    // MARK: - derived file names

    @Test("A name derives its three file locations, all inside the directory it is given")
    func derivedLocationsStayInsideTheDirectory() throws {
        let name = try SSHKeyName.validated("work_key").get()

        #expect(name.privateKeyURL(in: Self.directory).lastPathComponent == "work_key")
        #expect(name.publicKeyURL(in: Self.directory).lastPathComponent == "work_key.pub")
        #expect(name.certificateURL(in: Self.directory).lastPathComponent == "work_key-cert.pub")

        for url in name.derivedURLs(in: Self.directory) {
            #expect(url.deletingLastPathComponent().standardizedFileURL == Self.directory.standardizedFileURL)
        }
    }

    @Test("The public key location is the private key location plus the extension")
    func publicKeyLocationExtendsThePrivateOne() throws {
        let name = try SSHKeyName.validated("work_key").get()

        let expected = name.privateKeyURL(in: Self.directory).path(percentEncoded: false) + ".pub"

        #expect(name.publicKeyURL(in: Self.directory).path(percentEncoded: false) == expected)
    }

    // MARK: - names that came from the file system

    @Test("A name read off a directory listing skips the rules that govern user input")
    func discoveryBypassesTheUserInputRules() throws {
        // The reserved-name and `.pub` rules say what the user may *type*. A name that came
        // off a listing has already been written to disk by something else, so the only
        // question left is whether it could name one file. Whether such an entry is
        // *presented* is `SSHKeyDiscovery`'s decision, not this type's.
        #expect(SSHKeyName.discovered("config")?.rawValue == "config")
        #expect(SSHKeyName.discovered("odd.pub")?.rawValue == "odd.pub")
    }

    @Test("A name read off a listing is still refused where it could not name one file")
    func discoveryRefusesANameThatIsNotAFileName() {
        #expect(SSHKeyName.discovered("") == nil)
        #expect(SSHKeyName.discovered("nested/key") == nil)
        #expect(SSHKeyName.discovered("..") == nil)
    }

    // MARK: - ordering

    @Test("Names order alphabetically, which is what makes the presented list stable")
    func namesOrderAlphabetically() throws {
        let names = try ["work", "alpha", "beta"].map { try SSHKeyName.validated($0).get() }

        #expect(names.sorted().map(\.rawValue) == ["alpha", "beta", "work"])
    }

    // MARK: - reasons

    @Test("Every rejection states its own rule, and a collision names the file at risk")
    func everyRejectionStatesItsRule() {
        let collision = URL(filePath: "/fabricated/keys/work_key.pub")

        #expect(SSHKeyNameError.empty.reason.localizedCaseInsensitiveContains("empty"))
        #expect(SSHKeyNameError.notAPlainFileName("a/b").reason.localizedCaseInsensitiveContains("separator"))
        #expect(SSHKeyNameError.endsInPublicKeyExtension("a.pub").reason.contains(".pub"))
        #expect(SSHKeyNameError.reservedByOpenSSH("config").reason.localizedCaseInsensitiveContains("reserved"))
        #expect(SSHKeyNameError.wouldReplace(collision).reason.contains("work_key.pub"))
    }
}
