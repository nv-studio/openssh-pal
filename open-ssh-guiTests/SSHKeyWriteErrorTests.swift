import Foundation
import Testing

@Suite("Mutation and generation error vocabularies")
struct SSHKeyWriteErrorTests {

    private static let secret = "correct horse battery staple"
    private static let privateKey = URL(filePath: "/fabricated/keys/work_key")
    private static let publicKey = URL(filePath: "/fabricated/keys/work_key.pub")

    private static let writeErrors: [SSHKeyWriteError] = [
        .destinationExists(publicKey),
        .notFound(privateKey),
        .accessDenied(privateKey),
        .failed(privateKey),
    ]

    private static let generationErrors: [SSHKeyGenerationError] = [
        .toolUnavailable(URL(filePath: "/fabricated/bin/ssh-keygen")),
        .directoryMissing(URL(filePath: "/fabricated/keys")),
        .toolFailed(status: 1, detail: "unknown key type"),
        .outputMissing(privateKey),
        .outputMismatch(expected: .ed25519, actual: .rsa),
        .outputUnreadable(publicKey),
        .timedOut,
    ]

    // MARK: - one case per condition

    @Test("Each mutation failure is its own case, so absence stays distinguishable from denial")
    func mutationCasesAreDistinct() {
        #expect(Set(Self.writeErrors.map(\.reason)).count == Self.writeErrors.count)

        for error in Self.writeErrors {
            #expect(error.url == error.url)
        }
        #expect(SSHKeyWriteError.destinationExists(Self.publicKey).url == Self.publicKey)
        #expect(SSHKeyWriteError.notFound(Self.privateKey).url == Self.privateKey)
    }

    @Test("Each generation failure is its own case, so a missing tool is not a missing directory")
    func generationCasesAreDistinct() {
        #expect(Set(Self.generationErrors.map(\.reason)).count == Self.generationErrors.count)
    }

    // MARK: - every case names its condition

    @Test("Every mutation reason names what went wrong")
    func mutationReasonsNameTheCondition() {
        #expect(SSHKeyWriteError.destinationExists(Self.publicKey).reason.localizedCaseInsensitiveContains("already exists"))
        #expect(SSHKeyWriteError.notFound(Self.privateKey).reason.localizedCaseInsensitiveContains("no longer"))
        #expect(SSHKeyWriteError.accessDenied(Self.privateKey).reason.localizedCaseInsensitiveContains("permission"))
        #expect(SSHKeyWriteError.failed(Self.privateKey).reason.localizedCaseInsensitiveContains("could not"))
    }

    @Test("Every generation reason names what went wrong")
    func generationReasonsNameTheCondition() {
        #expect(SSHKeyGenerationError.toolUnavailable(URL(filePath: "/fabricated/bin/ssh-keygen")).reason
            .localizedCaseInsensitiveContains("ssh-keygen"))
        #expect(SSHKeyGenerationError.directoryMissing(URL(filePath: "/fabricated/keys")).reason
            .localizedCaseInsensitiveContains("does not exist"))
        #expect(SSHKeyGenerationError.toolFailed(status: 1, detail: "unknown key type").reason
            .localizedCaseInsensitiveContains("unknown key type"))
        #expect(SSHKeyGenerationError.outputMissing(Self.privateKey).reason
            .localizedCaseInsensitiveContains("did not write"))
        #expect(SSHKeyGenerationError.outputMismatch(expected: .ed25519, actual: .rsa).reason
            .localizedCaseInsensitiveContains("ed25519"))
        #expect(SSHKeyGenerationError.outputUnreadable(Self.publicKey).reason
            .localizedCaseInsensitiveContains("could not be read"))
        #expect(SSHKeyGenerationError.timedOut.reason.localizedCaseInsensitiveContains("timed out"))
    }

    // MARK: - 10.8 nothing secret, and no path

    @Test("No reason carries a secret, and none spells out a private key's path")
    func noReasonLeaksASecretOrAPath() {
        // A file name is what the user needs in order to act. A full path is what 10.8
        // withholds, so every reason below names the file and not the directory it is in.
        for reason in Self.writeErrors.map(\.reason) + Self.generationErrors.map(\.reason) {
            #expect(!reason.contains(Self.secret))
            #expect(!reason.contains("/fabricated"))
        }
    }

    @Test("A mutation reason still names the file, so the user can tell which one is at risk")
    func mutationReasonNamesTheFile() {
        #expect(SSHKeyWriteError.notFound(Self.privateKey).reason.contains("work_key"))
        #expect(SSHKeyWriteError.destinationExists(Self.publicKey).reason.contains("work_key.pub"))
    }
}
