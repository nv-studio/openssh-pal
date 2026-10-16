import Foundation
import Observation

/// Holds a host form's draft and decides what it offers, accepts and refuses.
///
/// Owns only draft state. Validation, key choices, the placement warning and whether the form
/// may be submitted are all derived from the draft on every read and never stored, so none of
/// them can disagree with the values on screen.
///
/// Every write is the configuration model's; this model only says what to write and against
/// which bytes.
@MainActor
@Observable
final class HostFormModel {

    // MARK: - State

    /// `nil` presents the host list; a mode presents the form in its place.
    private(set) var mode: HostFormMode?

    /// What the user has typed. Settable because the fields bind to it.
    var draft: HostDraft = .empty

    /// The declaring file's bytes when the form opened — `config`'s for a create, `nil` when
    /// there was none. An edit is computed from these and written only if the file still holds
    /// them, so a panel refresh while the form is open never moves the baseline.
    private(set) var baseline: Data?

    private(set) var isSaving = false

    /// The key choice the form opened with, so saving an untouched key does not rewrite how
    /// its `IdentityFile` is spelled.
    private var initialKeyChoice: HostKeyChoice = .none

    // MARK: - Dependencies

    private let configuration: SSHConfigModel
    private let keys: SSHKeyListModel
    private let validator = HostDraftValidator()

    init(configuration: SSHConfigModel, keys: SSHKeyListModel) {
        self.configuration = configuration
        self.keys = keys
    }

    // MARK: - Opening and leaving

    func beginCreate() {
        mode = .create
        draft = .empty
        initialKeyChoice = .none
        baseline = configuration.configBaseline
    }

    func beginEdit(_ entry: HostEntry) {
        let choice = initialChoice(for: entry)

        mode = .edit(entry)
        baseline = configuration.baseline(for: entry)
        initialKeyChoice = choice
        draft = HostDraft(
            patterns: entry.displayName,
            hostName: entry.hostName?.value ?? "",
            user: entry.user?.value ?? "",
            port: entry.port?.value ?? "",
            keyChoice: choice
        )
    }

    /// Returns to the list without writing anything. Also what leaving the Hosts tab does.
    func discard() {
        mode = nil
        draft = .empty
        baseline = nil
        initialKeyChoice = .none
    }

    /// The choice that represents what the block already says, or `.unchanged` when no single
    /// choice can: several `IdentityFile` lines, one that does not resolve to a listed pair, or
    /// one naming a pair whose private key is gone.
    private func initialChoice(for entry: HostEntry) -> HostKeyChoice {
        let associations = keyIndex.associations(for: entry.id)
        if associations.isEmpty { return .none }

        guard associations.count == 1, case .listed(let name) = associations[0],
              keys.state.pairs.contains(where: { $0.id == name && !$0.isPrivateKeyMissing })
        else { return .unchanged }
        return .pair(name)
    }

    // MARK: - Read-only fields

    /// Why a field cannot be edited in this form, or `nil` where it can.
    func readOnlyReason(for field: HostDraftField) -> String? {
        guard let entry = mode?.editedEntry else { return nil }

        switch field {
        case .patterns:
            guard entry.patterns.contains(where: { $0.text.contains(where: \.isWhitespace) }) else { return nil }
            return "A pattern contains a space, so the patterns can only be changed in the file itself."
        case .hostName:
            return repeatedReason(.hostName, field: field, in: entry)
        case .user:
            return repeatedReason(.user, field: field, in: entry)
        case .port:
            return repeatedReason(.port, field: field, in: entry)
        }
    }

    /// Clearing the first of a repeated value would silently promote the second, so the form
    /// leaves it to the file.
    private func repeatedReason(_ keyword: SSHConfigKeyword, field: HostDraftField, in entry: HostEntry) -> String? {
        guard entry.repeatedKeywords.contains(keyword) else { return nil }
        return "\(field.title) is declared more than once in this block and ssh uses the first; change it in the file itself."
    }

    // MARK: - Keys

    private var keyIndex: HostKeyIndex {
        configuration.keyIndex(for: keys.state.pairs)
    }

    /// What the key picker offers, in order.
    var keyChoices: [HostKeyChoiceOption] {
        let index = keyIndex
        let edited = mode?.editedEntry
        var options: [HostKeyChoiceOption] = []

        if let edited, initialKeyChoice == .unchanged {
            options.append(
                HostKeyChoiceOption(
                    choice: .unchanged,
                    title: "Keep current",
                    detail: edited.identityFiles.map(\.value).joined(separator: ", "),
                    isAvailable: true,
                    sharingHosts: []
                )
            )
        }

        options.append(
            HostKeyChoiceOption(
                choice: .none,
                title: "No key",
                detail: "ssh uses its default identities",
                isAvailable: true,
                sharingHosts: []
            )
        )

        for pair in keys.state.pairs {
            options.append(
                HostKeyChoiceOption(
                    choice: .pair(pair.id),
                    title: pair.displayName,
                    detail: pair.isPrivateKeyMissing ? "The private key is missing" : pair.typeText,
                    isAvailable: !pair.isPrivateKeyMissing,
                    sharingHosts: index.hosts(using: pair.id, excluding: edited?.id)
                )
            )
        }

        return options
    }

    /// Said in place of the pairs when there are none.
    var noKeysMessage: String? {
        keys.state.pairs.isEmpty ? "No key pairs exist in the SSH directory." : nil
    }

    /// Chooses a key. A choice that is not available is ignored rather than trusted.
    func select(_ choice: HostKeyChoice) {
        guard keyChoices.contains(where: { $0.choice == choice && $0.isAvailable }) else { return }
        draft.keyChoice = choice
    }

    /// Names the other hosts using the selected key. Advisory: it never blocks submitting.
    var selectedKeyStatus: String? {
        guard let option = keyChoices.first(where: { $0.choice == draft.keyChoice }), option.isShared else { return nil }
        return "Also used by \(option.sharingHosts.joined(separator: ", "))."
    }

    // MARK: - Validation

    private var validation: Result<ValidatedHostDraft, HostDraftErrors>? {
        guard let mode else { return nil }
        return validator.validate(draft, mode: mode, existing: configuration.entries)
    }

    /// One field's verdict, in the design system's vocabulary.
    func fieldValidation(for field: HostDraftField) -> FieldValidation {
        guard case .failure(let errors) = validation, let error = errors.byField[field] else { return .valid }
        return .invalid(error.reason)
    }

    /// Whether the confirming control may be offered. Derived, never stored.
    var canSubmit: Bool {
        guard case .success = validation, !isSaving, !configuration.operation.isInFlight else { return false }
        if let entry = mode?.editedEntry {
            return entry.writability.isWritable && baseline != nil
        }
        return true
    }

    // MARK: - Placement

    /// Set in create mode when a block the new one cannot be placed above would pre-empt its
    /// values. The view gates submitting behind it; the user may still proceed.
    var placementWarning: HostPlacementWarning? {
        guard mode == .create, case .success(let validated) = validation,
              let decision = configuration.placement(for: validated.alias),
              !decision.precedingMatches.isEmpty
        else { return nil }

        let blocks = decision.precedingMatches.map { match in
            "Host \(match.displayName) in \(configuration.displayPath(of: match.file))"
                + (match.isConditional ? " (when its Match block applies)" : "")
        }
        return HostPlacementWarning(
            title: "Earlier settings take precedence",
            message: """
                ssh reads \(blocks.joined(separator: "; ")) before the new block, so any value \
                set there wins for \(validated.alias).
                """
        )
    }

    // MARK: - Submitting

    /// Writes the draft. Returns to the list when it was written, or when the file changed
    /// underneath it and the draft no longer describes the file; stays open after a failure so
    /// nothing typed is lost.
    func submit() async {
        guard canSubmit, case .success(let validated) = validation, let mode else { return }

        isSaving = true
        defer { isSaving = false }

        let outcome: ConfigMutationOutcome
        switch mode {
        case .create:
            outcome = await configuration.create(validated, baseline: baseline)
        case .edit(let entry):
            guard let baseline else { return }
            let draft = validated.keyChoice == initialKeyChoice ? validated.with(keyChoice: .unchanged) : validated
            outcome = await configuration.update(entry, with: draft, baseline: baseline)
        }

        if outcome == .completed || outcome == .changedOnDisk {
            discard()
        }
    }
}
