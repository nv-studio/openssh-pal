import Foundation
import Observation

/// Holds the create form's state, validates it, and runs generation.
///
/// Two things here are load-bearing rather than incidental.
///
/// **The passphrase is stored as a `Passphrase`, not a `String`.** The text fields bind to a
/// computed accessor over it, so there is one place the secret lives, it redacts itself
/// wherever it is described, and dropping it on every exit path is a single assignment.
///
/// **Generation is the model's own `Task`, never a view's.** A `task` modifier is cancelled
/// when its view goes away, and the panel goes away whenever the user clicks outside it — so
/// a key half-written when the panel dismissed would be the result. The model owns the task
/// and keeps the outcome until something asks for it.
@MainActor
@Observable
final class NewKeyFormModel {

    // MARK: - Field values

    var name = ""
    var comment = ""

    /// The selected type. Only ever a whole type, never a type plus a loose parameter: the
    /// type cannot hold a parameter that does not apply to it, so discarding an inapplicable
    /// one is not a rule to enforce but a consequence of the assignment.
    private(set) var type: SSHKeyType = .default

    /// The entered passphrase. `private(set)` so the only mutation path is the text accessor
    /// below, which keeps "one place holds the secret" true.
    private(set) var passphrase: Passphrase = .none

    /// The confirmation, held separately because the whole point is to compare two
    /// independent entries.
    private(set) var confirmation: Passphrase = .none

    /// Whether the user has asked to see what they typed.
    ///
    /// The secret field reports a reveal request and does not act on it, so the policy is
    /// this model's: redacted until asked, and reset whenever the form is opened or left.
    private(set) var isPassphraseRevealed = false

    // MARK: - Progress and outcome

    private(set) var isGenerating = false

    /// Why the last attempt failed, or `nil` where it did not.
    private(set) var failureReason: String?

    /// How the form finished, or `nil` while it has not.
    private(set) var completion: NewKeyFormCompletion?

    // MARK: - Dependencies

    private let generator: SSHKeyGenerating

    /// The comment to propose. Supplied rather than derived, because the user name and host
    /// name come from the process and only the composition root may ask for those.
    private let defaultComment: String

    private let validator = SSHKeyNameValidator()

    /// Where the key will be written, and what is already there. Both arrive when the form is
    /// opened: without them the collision rule has nothing to check against, so a form that
    /// was never opened cannot generate.
    private var directory: SSHDirectory?
    private var entries: [URL] = []

    /// The task generation runs on. Owned here, so panel dismissal does not cancel it.
    private var generation: Task<Void, Never>?

    init(generator: SSHKeyGenerating, defaultComment: String) {
        self.generator = generator
        self.defaultComment = defaultComment
    }

    // MARK: - Opening and leaving

    /// Opens the form against a directory and its current contents.
    ///
    /// The proposed name follows the selected type, as `ssh-keygen`'s own default does, and is
    /// proposed once: it is not rewritten when the type changes, because by then the user may
    /// have replaced it.
    func begin(in directory: SSHDirectory, existing entries: [URL]) {
        self.directory = directory
        self.entries = entries

        type = .default
        name = "id_\(type.keygenTypeName)"
        comment = defaultComment
        clearSecrets()
        failureReason = nil
        completion = nil
    }

    /// Discards everything entered, without writing anything.
    func cancel() {
        clearSecrets()
        failureReason = nil
        completion = .cancelled
    }

    /// Leaves the form without finishing it: what the user leaving its tab means.
    ///
    /// Unlike `cancel()`, this produces no completion, because the panel adopts a completion by
    /// switching to the Keys tab — which would yank the user away from the tab they just chose.
    ///
    /// Does nothing while a generation runs. The generation is the model's own task and must
    /// finish, and its outcome must still be there when the user comes back; dropping the form's
    /// state now would lose it.
    func discard() {
        guard !isGenerating else { return }
        directory = nil
        entries = []
        name = ""
        comment = ""
        type = .default
        clearSecrets()
        failureReason = nil
    }

    /// Drops both secrets and the reveal flag.
    ///
    /// This is the whole of what "retain no reference" can mean for a value type — see
    /// `Passphrase` for why memory scrubbing is not claimed.
    private func clearSecrets() {
        passphrase = .none
        confirmation = .none
        isPassphraseRevealed = false
    }

    // MARK: - Type selection

    /// The types on offer, so no view enumerates them.
    var families: [SSHKeyTypeFamily] { SSHKeyTypeFamily.allCases }

    var rsaLengths: [RSAKeyLength] { RSAKeyLength.allCases }

    var curves: [ECDSACurve] { ECDSACurve.allCases }

    /// The selected RSA length, or `nil` where RSA is not selected — which is also what tells
    /// the form whether to offer the control at all.
    var rsaLength: RSAKeyLength? {
        guard case .rsa(let length) = type else { return nil }
        return length
    }

    var curve: ECDSACurve? {
        guard case .ecdsa(let curve) = type else { return nil }
        return curve
    }

    /// Selects a family, taking its proposed parameter with it.
    func select(_ family: SSHKeyTypeFamily) {
        type = family.defaultType
    }

    /// Selects an RSA length. Ignored unless RSA is the selected family, because there is
    /// nowhere to put it otherwise.
    func select(_ length: RSAKeyLength) {
        guard case .rsa = type else { return }
        type = .rsa(length)
    }

    func select(_ curve: ECDSACurve) {
        guard case .ecdsa = type else { return }
        type = .ecdsa(curve)
    }

    // MARK: - The passphrase fields

    /// The passphrase as editable text.
    ///
    /// A computed accessor over the `Passphrase` rather than a stored `String`, so the secret
    /// has exactly one home and cannot be left behind in a second property.
    var passphraseText: String {
        get { passphrase.secret }
        set { passphrase = Passphrase(newValue) }
    }

    var confirmationText: String {
        get { confirmation.secret }
        set { confirmation = Passphrase(newValue) }
    }

    /// How much of the passphrase the secret field has been authorised to show.
    var passphrasePresentation: SecretPresentation {
        isPassphraseRevealed
            ? .revealed(passphrase.secret)
            : .redacted(placeholderLength: passphrase.secret.count)
    }

    func revealPassphrase() {
        isPassphraseRevealed = true
    }

    func hidePassphrase() {
        isPassphraseRevealed = false
    }

    // MARK: - Validation

    private var nameOutcome: Result<SSHKeyName, SSHKeyNameError>? {
        guard let directory else { return nil }
        return validator.validate(name, in: directory.url, against: entries, replacing: nil)
    }

    var nameValidation: FieldValidation {
        switch nameOutcome {
        case .none:
            .invalid("No SSH directory to write to.")
        case .success:
            .valid
        case .failure(let error):
            .invalid(error.reason)
        }
    }

    /// The mismatch check. This is the only place a mismatch can be caught: the generator
    /// writes one buffer twice, so by the time the two prompts are answered they cannot
    /// differ.
    var passphraseValidation: FieldValidation {
        passphrase == confirmation ? .valid : .invalid("The two passphrases do not match.")
    }

    /// What an empty passphrase means, or `nil` where one was supplied.
    ///
    /// Stated rather than prevented: an unencrypted key is a legitimate choice, and the user
    /// is told what they are choosing.
    var passphraseNotice: String? {
        passphrase.isEmpty ? "With no passphrase, the private key is stored unencrypted." : nil
    }

    /// Whether generation may be started. Derived from the field verdicts, never stored, so
    /// it cannot disagree with the messages beside the fields.
    var canGenerate: Bool {
        guard !isGenerating, directory != nil else { return false }
        return nameValidation.isValid && passphraseValidation.isValid
    }

    // MARK: - Generation

    /// Starts generation on a task this model owns.
    ///
    /// Non-`async` on purpose: an `async` submit would tie the work to whatever awaited it,
    /// and the only caller is a button in a view that may be gone a moment later.
    func submit() {
        guard canGenerate,
              let directory,
              case .success(let name) = nameOutcome
        else { return }

        let request = SSHKeyGenerationRequest(name: name, type: type, comment: comment)
        let passphrase = passphrase

        isGenerating = true
        failureReason = nil

        generation = Task { [generator] in
            switch await Self.run(request, passphrase: passphrase, in: directory, using: generator) {
            case .success(let pair):
                finish(with: .created(pair))
            case .failure(let error):
                fail(with: error)
            }
        }
    }

    /// Calls the port and turns its typed failure into a value.
    ///
    /// Separate from `submit` because a `Task` closure erases the port's typed `throws` back
    /// to `any Error`, which would lose exactly the type the caller needs to switch on.
    private static func run(
        _ request: SSHKeyGenerationRequest,
        passphrase: Passphrase,
        in directory: SSHDirectory,
        using generator: SSHKeyGenerating
    ) async -> Result<SSHKeyPair, SSHKeyGenerationError> {
        do {
            return .success(try await generator.generate(request, passphrase: passphrase, in: directory))
        } catch {
            return .failure(error)
        }
    }

    /// Clears the outcome once the panel has acted on it, so reopening the form does not
    /// immediately complete again.
    func acknowledgeCompletion() {
        completion = nil
    }

    /// Awaits an in-flight generation. For the panel, which must not lose an outcome, and for
    /// the tests, which must not race it.
    func waitForGeneration() async {
        await generation?.value
    }

    private func finish(with completion: NewKeyFormCompletion) {
        isGenerating = false
        clearSecrets()
        self.completion = completion
    }

    private func fail(with error: SSHKeyGenerationError) {
        isGenerating = false
        // Dropped here too: the attempt is over, whether or not it worked.
        clearSecrets()
        failureReason = error.reason
    }
}
