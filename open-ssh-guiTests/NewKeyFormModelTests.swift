import Foundation
import Testing

/// Generation is driven entirely through `StubSSHKeyGenerator`. No test here launches
/// `ssh-keygen` or writes a file, and the directory and listing the form validates against
/// are fabricated values.
@MainActor
@Suite("Create form model")
struct NewKeyFormModelTests {

    nonisolated private static let keys = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)
    private static let directory = SSHDirectory(url: keys)

    nonisolated private static func file(_ name: String) -> URL {
        keys.appending(path: name)
    }

    nonisolated private static func pair(_ raw: String, type: SSHKeyType = .ed25519) -> SSHKeyPair {
        let name = SSHKeyName.discovered(raw)!
        return SSHKeyPair(
            location: SSHKeyPairLocation(
                name: name,
                publicKeyURL: name.publicKeyURL(in: keys),
                privateKeyURL: name.privateKeyURL(in: keys),
                certificateURL: nil
            ),
            publicKey: .success(
                SSHPublicKey(
                    algorithm: .ed25519,
                    bitLength: type.expectedBitLength,
                    fingerprint: SSHFingerprint(value: "SHA256:fabricated"),
                    comment: "user@host"
                )
            )
        )
    }

    /// A form already opened against a directory holding `entries`.
    private static func form(
        entries: [String] = [],
        generator: StubSSHKeyGenerator = StubSSHKeyGenerator(outcome: .success(pair("id_ed25519"))),
        comment: String = "user@host"
    ) -> NewKeyFormModel {
        let model = NewKeyFormModel(generator: generator, defaultComment: comment)
        model.begin(in: directory, existing: entries.map(file))
        return model
    }

    // MARK: - 8.2 / 8.3 / 8.6 what the form collects

    @Test("The form proposes a name and a comment the user can replace")
    func formProposesDefaults() {
        let form = Self.form()

        #expect(form.name == "id_ed25519")
        #expect(form.comment == "user@host")

        form.name = "work_key"
        form.comment = "me@laptop"

        #expect(form.name == "work_key")
        #expect(form.comment == "me@laptop")
    }

    @Test("Ed25519 is selected by default, because it is what OpenSSH recommends")
    func ed25519IsSelectedByDefault() {
        #expect(Self.form().type == .ed25519)
        #expect(Self.form().type.family == .ed25519)
    }

    @Test("All three key types are offered")
    func allThreeTypesAreOffered() {
        #expect(SSHKeyTypeFamily.allCases.count == 3)
        #expect(Self.form().families == SSHKeyTypeFamily.allCases)
    }

    // MARK: - 8.4 / 8.5 only the applicable parameters

    @Test("Only the selected type's parameters are offered")
    func onlyApplicableParametersAreOffered() {
        let form = Self.form()

        #expect(form.rsaLength == nil)
        #expect(form.curve == nil)

        form.select(.rsa)
        #expect(form.rsaLength != nil)
        #expect(form.curve == nil)

        form.select(.ecdsa)
        #expect(form.rsaLength == nil)
        #expect(form.curve != nil)
    }

    @Test("Changing the type discards a parameter that no longer applies")
    func changingTypeDiscardsAnInapplicableParameter() {
        let form = Self.form()

        form.select(.rsa)
        form.select(.bits2048)
        #expect(form.type == .rsa(.bits2048))

        form.select(.ecdsa)
        #expect(form.type == .ecdsa(.nistp256))

        // Returning to RSA starts from the family's own proposal, not from the 2048 that was
        // chosen before — the old parameter was not retained anywhere, because the type
        // cannot hold both.
        form.select(.rsa)
        #expect(form.type == .rsa(.bits4096))
    }

    @Test("A parameter for a type that is not selected is ignored rather than stored")
    func inapplicableParameterIsIgnored() {
        let form = Self.form()

        // Ed25519 is selected; it has no size.
        form.select(.bits2048)

        #expect(form.type == .ed25519)
    }

    // MARK: - 5.1-5.5 / 8.9 name validation

    @Test("A rejected name keeps the generate control unavailable and says which value is wrong")
    func rejectedNameBlocksGeneration() {
        let form = Self.form()

        for rejected in ["", "  ", "a/b", "k.pub", "config"] {
            form.name = rejected

            #expect(!form.canGenerate, "\(rejected) should not be generatable")
            #expect(form.nameValidation != .valid)
        }
    }

    @Test("A name that would replace an existing file is rejected, naming that file")
    func collidingNameIsRejected() {
        let form = Self.form(entries: ["taken", "taken.pub"])

        form.name = "taken"

        #expect(!form.canGenerate)
        #expect(form.nameValidation.message?.contains("taken") == true)
    }

    @Test("A name no rule rejects makes the form generatable")
    func acceptableNameIsGeneratable() {
        let form = Self.form()

        form.name = "work_key"

        #expect(form.nameValidation == .valid)
        #expect(form.canGenerate)
    }

    // MARK: - 8.7 the passphrase is entered twice

    @Test("A mismatched passphrase is reported before generation is attempted")
    func mismatchIsReportedBeforeGeneration() async {
        let generator = StubSSHKeyGenerator(outcome: .success(Self.pair("work_key")))
        let form = Self.form(generator: generator)

        form.passphraseText = "hunter2"
        form.confirmationText = "hunter3"

        #expect(!form.canGenerate)
        #expect(form.passphraseValidation != .valid)

        form.submit()
        await form.waitForGeneration()

        // The generator writes one buffer twice, so a mismatch has nowhere else to be
        // caught. Nothing was sent.
        #expect(generator.callCount == 0)
    }

    @Test("A matching passphrase clears the mismatch")
    func matchingPassphraseIsAccepted() {
        let form = Self.form()

        form.passphraseText = "hunter2"
        form.confirmationText = "hunter2"

        #expect(form.passphraseValidation == .valid)
        #expect(form.canGenerate)
    }

    // MARK: - 8.8 an empty passphrase

    @Test("An empty passphrase is allowed, and the form states what it means")
    func emptyPassphraseIsAllowedWithAWarning() throws {
        let form = Self.form()

        #expect(form.passphraseText.isEmpty)
        #expect(form.canGenerate)
        #expect(try #require(form.passphraseNotice).localizedCaseInsensitiveContains("unencrypted"))
    }

    @Test("A supplied passphrase replaces the unencrypted warning")
    func suppliedPassphraseRemovesTheWarning() {
        let form = Self.form()

        form.passphraseText = "hunter2"
        form.confirmationText = "hunter2"

        #expect(form.passphraseNotice == nil)
    }

    // MARK: - 10.6 the reveal flag

    @Test("The passphrase is redacted until the user asks for it, and the form owns that choice")
    func revealIsTheFormsChoice() {
        let form = Self.form()
        form.passphraseText = "hunter2"

        #expect(!form.isPassphraseRevealed)
        #expect(form.passphrasePresentation == .redacted(placeholderLength: 7))

        form.revealPassphrase()

        #expect(form.isPassphraseRevealed)
        #expect(form.passphrasePresentation == .revealed("hunter2"))
    }

    // MARK: - 10.4 / 10.8 the passphrase is not printable

    @Test("Interpolating the form's passphrase anywhere yields the redaction marker")
    func passphraseCannotBeInterpolated() {
        let form = Self.form()
        form.passphraseText = "hunter2"

        #expect("\(form.passphrase)" == Passphrase.redactedMarker)
    }

    // MARK: - 8.10 / 10.7 cancelling

    @Test("Cancelling discards every entered value and writes nothing")
    func cancellingDiscardsEverything() async {
        let generator = StubSSHKeyGenerator(outcome: .success(Self.pair("work_key")))
        let form = Self.form(generator: generator)
        form.name = "work_key"
        form.comment = "me@laptop"
        form.passphraseText = "hunter2"
        form.confirmationText = "hunter2"
        form.revealPassphrase()

        form.cancel()

        #expect(form.completion == .cancelled)
        #expect(form.passphrase == .none)
        #expect(form.passphraseText.isEmpty)
        #expect(form.confirmationText.isEmpty)
        #expect(!form.isPassphraseRevealed)
        // Nothing was generated, so nothing was written.
        #expect(generator.callCount == 0)
    }

    @Test("The passphrase is dropped on success as well as on cancel")
    func passphraseIsDroppedOnSuccess() async {
        let form = Self.form()
        form.name = "work_key"
        form.passphraseText = "hunter2"
        form.confirmationText = "hunter2"

        form.submit()
        await form.waitForGeneration()

        #expect(form.passphrase == .none)
        #expect(form.confirmationText.isEmpty)
    }

    @Test("The passphrase is dropped on failure too")
    func passphraseIsDroppedOnFailure() async {
        let generator = StubSSHKeyGenerator(outcome: .failure(.timedOut))
        let form = Self.form(generator: generator)
        form.name = "work_key"
        form.passphraseText = "hunter2"
        form.confirmationText = "hunter2"

        form.submit()
        await form.waitForGeneration()

        #expect(form.passphrase == .none)
    }

    // MARK: - 9.1 what reaches the generator

    @Test("The request carries the name, type and comment the user supplied, and the passphrase separately")
    func requestCarriesWhatTheUserSupplied() async throws {
        let generator = StubSSHKeyGenerator(outcome: .success(Self.pair("work_key")))
        let form = Self.form(generator: generator)
        form.name = "work_key"
        form.comment = "me@laptop"
        form.select(.rsa)
        form.select(.bits3072)
        form.passphraseText = "hunter2"
        form.confirmationText = "hunter2"

        form.submit()
        await form.waitForGeneration()

        let request = try #require(generator.requests.first)
        #expect(request.name.rawValue == "work_key")
        #expect(request.type == .rsa(.bits3072))
        #expect(request.comment == "me@laptop")
        #expect(generator.passphrases == [Passphrase("hunter2")])
        #expect(generator.directories == [Self.directory])
    }

    // MARK: - 9.3 while generation runs

    @Test("While generation runs the form reports progress and refuses a second submission")
    func generationInFlightBlocksASecondSubmission() async {
        let generator = StubSSHKeyGenerator(outcome: .success(Self.pair("work_key")))
        generator.hold()
        let form = Self.form(generator: generator)
        form.name = "work_key"

        form.submit()
        await Task.yield()

        #expect(form.isGenerating)
        #expect(!form.canGenerate)

        form.submit()
        generator.release()
        await form.waitForGeneration()

        #expect(generator.callCount == 1)
        #expect(!form.isGenerating)
    }

    // MARK: - 9.4 success

    @Test("A completed generation reports the new pair, with the attributes that were requested")
    func successReportsTheNewPair() async throws {
        let created = Self.pair("work_key")
        let form = Self.form(generator: StubSSHKeyGenerator(outcome: .success(created)))
        form.name = "work_key"

        form.submit()
        await form.waitForGeneration()

        #expect(form.completion == .created(created))
        let pair = try #require(form.completion?.createdPair)
        #expect(pair.parsedPublicKey?.algorithm == .ed25519)
        #expect(pair.parsedPublicKey?.bitLength == 256)
        #expect(pair.parsedPublicKey?.comment == "user@host")
        #expect(form.failureReason == nil)
    }

    // MARK: - 9.5 / 9.6 / 9.7 failures

    @Test("Each generation failure is reported with its own reason, and nothing is completed")
    func eachFailureIsReported() async throws {
        let failures: [SSHKeyGenerationError] = [
            .toolUnavailable(URL(filePath: "/fabricated/bin/ssh-keygen")),
            .directoryMissing(Self.keys),
            .outputMismatch(expected: .ed25519, actual: .rsa),
            .timedOut,
        ]

        for failure in failures {
            let form = Self.form(generator: StubSSHKeyGenerator(outcome: .failure(failure)))
            form.name = "work_key"

            form.submit()
            await form.waitForGeneration()

            #expect(form.failureReason == failure.reason)
            #expect(form.completion == nil, "a failure must not complete the form")
            #expect(!form.isGenerating)
        }
    }

    @Test("A failure leaves the form usable, so the user can correct and try again")
    func failureLeavesTheFormUsable() async {
        let generator = StubSSHKeyGenerator(outcome: .failure(.timedOut))
        let form = Self.form(generator: generator)
        form.name = "work_key"

        form.submit()
        await form.waitForGeneration()

        #expect(form.canGenerate)
        generator.setOutcome(.success(Self.pair("work_key")))

        form.submit()
        await form.waitForGeneration()

        #expect(form.completion != nil)
        #expect(form.failureReason == nil)
    }

    // MARK: - 9.8 generation outlives the panel

    @Test("Generation is the model's own task, so it finishes even if nobody is waiting")
    func generationIsOwnedByTheModel() async throws {
        let created = Self.pair("work_key")
        let generator = StubSSHKeyGenerator(outcome: .success(created))
        generator.hold()
        let form = Self.form(generator: generator)
        form.name = "work_key"

        form.submit()
        await Task.yield()

        // Nothing is awaiting the task at this point — which is the situation when the user
        // dismisses the panel. The outcome is still there to be presented afterwards.
        generator.release()
        await form.waitForGeneration()

        #expect(form.completion == .created(created))
    }

    @Test("A form that has not been opened against a directory cannot generate")
    func formWithoutADirectoryCannotGenerate() async {
        let generator = StubSSHKeyGenerator(outcome: .success(Self.pair("work_key")))
        let form = NewKeyFormModel(generator: generator, defaultComment: "user@host")

        form.submit()
        await form.waitForGeneration()

        #expect(!form.canGenerate)
        #expect(generator.callCount == 0)
    }

    // MARK: - reopening

    @Test("Reopening the form starts from the proposals again rather than the last attempt")
    func reopeningResetsTheForm() {
        let form = Self.form()
        form.name = "work_key"
        form.passphraseText = "hunter2"
        form.cancel()

        form.begin(in: Self.directory, existing: [])

        #expect(form.name == "id_ed25519")
        #expect(form.passphraseText.isEmpty)
        #expect(form.completion == nil)
        #expect(form.failureReason == nil)
    }
}
