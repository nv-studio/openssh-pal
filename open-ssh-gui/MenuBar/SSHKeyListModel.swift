import Foundation
import Observation

/// Orchestrates everything the key list does: enumerate, copy, rename and delete.
///
/// `@MainActor @Observable`, and the single source of truth for what the list presents. It
/// composes the pure rules with the ports and contains no parsing, validation or planning of
/// its own — each of those is a separate type, tested on its own.
///
/// No initializer parameter has a default value, following `SSHDirectoryStatusModel`:
/// forgetting to inject a port is then a compile error rather than a silent fallback to the
/// real file system, which for a component that moves and deletes files in `~/.ssh` is the
/// difference between a failing build and a lost key.
///
/// The pure rules are *not* injected. They are stateless functions over values, tested
/// directly, and making them seams would suggest they are worth faking — which would hide
/// that this model has no logic of its own to fake around.
@MainActor
@Observable
final class SSHKeyListModel {

    // MARK: - Presented state

    private(set) var state: SSHKeyListState = .loading

    /// Whether an enumeration is in flight. Separate from `state` so a refresh does not
    /// throw the list away and leave the panel blank while it re-reads.
    private(set) var isRefreshing = false

    /// The mutation in flight. No case for two, which is what refuses a second one.
    private(set) var operation: KeyOperation = .idle

    /// The outcome of the last thing the user asked for.
    private(set) var notice: KeyListNotice?

    /// The pair being renamed, or `nil` when no rename is being composed.
    private(set) var renamingPair: SSHKeyPair?

    /// The name the user is editing. Settable because the field binds to it.
    var renameProposal = ""

    // MARK: - Dependencies

    private let status: SSHDirectoryStatusModel
    private let reader: SSHDirectoryReading
    private let writer: SSHKeyWriting
    private let clipboard: ClipboardWriting

    private let discovery = SSHKeyDiscovery()
    private let parser = SSHPublicKeyParser()
    private let validator = SSHKeyNameValidator()

    /// The directory and listing the last enumeration saw.
    ///
    /// Held so that name validation — which needs to know what the directory already
    /// contains — stays synchronous, and so the confirming control's availability can be
    /// derived as the user types rather than awaited.
    private var directory: SSHDirectory?
    private var entries: [URL] = []

    init(
        status: SSHDirectoryStatusModel,
        reader: SSHDirectoryReading,
        writer: SSHKeyWriting,
        clipboard: ClipboardWriting
    ) {
        self.status = status
        self.reader = reader
        self.writer = writer
        self.clipboard = clipboard
    }

    // MARK: - Enumeration

    /// Re-reads the directory. Driven on each panel open and after every completed mutation.
    ///
    /// Never throws: every failure becomes a state instead, which is what keeps the panel
    /// usable — and quittable — when the directory is missing or unreadable.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        await status.refresh()

        switch status.status {
        case .resolving:
            // Unreachable after an awaited refresh; treated as still loading rather than
            // asserted, because a crash here would cost the user their only way to quit.
            state = .loading
        case .unresolved(let error):
            directory = nil
            entries = []
            state = .noDirectory(error)
        case .unreadable(let resolved, let error):
            directory = resolved
            entries = []
            state = .unreadable(error)
        case .reachable(let resolved):
            directory = resolved
            state = await listing(of: resolved)
        }
    }

    private func listing(of directory: SSHDirectory) async -> SSHKeyListState {
        do {
            let entries = try await reader.entries(in: directory.url)
            self.entries = entries

            var pairs: [SSHKeyPair] = []
            for location in discovery.pairLocations(in: entries) {
                pairs.append(await pair(at: location))
            }
            return .loaded(pairs)
        } catch {
            entries = []
            return .unreadable(error)
        }
    }

    /// One pair, with its public key read and parsed.
    ///
    /// A file that cannot be read and a file that is not a key are different facts and are
    /// reported differently, but neither drops the entry: the user still needs to be told
    /// which file in their SSH directory is not what it appears to be.
    private func pair(at location: SSHKeyPairLocation) async -> SSHKeyPair {
        guard let contents = try? await reader.contents(of: location.publicKeyURL) else {
            return SSHKeyPair(location: location, publicKey: .failure(.fileUnreadable))
        }
        return SSHKeyPair(location: location, publicKey: parser.parse(contents))
    }

    func dismissNotice() {
        notice = nil
    }

    /// The directory the last enumeration resolved, and what it held.
    ///
    /// Exposed so the create form can be opened against the same directory and listing this
    /// model validated against — which is what keeps one collision rule serving both
    /// operations instead of each reading the directory for itself.
    var resolvedDirectory: SSHDirectory? { directory }

    var directoryEntries: [URL] { entries }

    /// Presents a pair the create form produced, and re-enumerates so the list holds it.
    func acknowledge(created pair: SSHKeyPair) async {
        notice = .generated(pair.id)
        await refresh()
    }

    // MARK: - Copying

    /// Reads the pair's public key and puts it on the clipboard.
    ///
    /// The port is handed text rather than a path, so there is no call this method could make
    /// that would reach a private key — which is what makes "never copy a private key"
    /// structural rather than a rule to remember.
    func copyPublicKey(of pair: SSHKeyPair) async {
        do {
            let contents = try await reader.contents(of: pair.location.publicKeyURL)
            await clipboard.write(String(decoding: contents, as: UTF8.self))
            notice = .copied(pair.id)
        } catch {
            // The clipboard is never reached, so it keeps whatever it held.
            notice = .failed(reason: error.reason)
        }
    }

    // MARK: - Renaming

    /// Offers the pair's current name for editing.
    func beginRename(of pair: SSHKeyPair) {
        guard !operation.isInFlight else { return }
        renamingPair = pair
        renameProposal = pair.displayName
        notice = nil
    }

    func cancelRename() {
        renamingPair = nil
        renameProposal = ""
    }

    /// The validated name, or why it was rejected. `nil` when no rename is being composed.
    private var renameOutcome: Result<SSHKeyName, SSHKeyNameError>? {
        guard let renamingPair, let directory else { return nil }
        return validator.validate(
            renameProposal,
            in: directory.url,
            against: entries,
            replacing: renamingPair.id
        )
    }

    /// The field's verdict, in the design system's own vocabulary.
    var renameValidation: FieldValidation {
        switch renameOutcome {
        case .none, .success:
            .valid
        case .failure(let error):
            .invalid(error.reason)
        }
    }

    /// Whether the confirming control may be offered. Derived, never stored, so it cannot
    /// disagree with the field's verdict.
    var canConfirmRename: Bool {
        guard case .success = renameOutcome, !operation.isInFlight else { return false }
        return true
    }

    /// The title of the warning shown before a rename proceeds.
    var renameWarningTitle: String? {
        guard canConfirmRename else { return nil }
        return "Rename \(renamingPair?.displayName ?? "")?"
    }

    /// The warning itself, naming both paths.
    ///
    /// The app does not update what points at a key — `IdentityFile` lines, scripts,
    /// `ssh-add` invocations, anything in a CI configuration — so it says so, and names the
    /// two paths rather than leaving the user to work out what changed.
    var renameWarningMessage: String? {
        guard case .success(let newName) = renameOutcome,
              let pair = renamingPair,
              let directory
        else { return nil }

        let from = pair.location.privateKeyURL ?? pair.location.publicKeyURL
        let to = newName.privateKeyURL(in: directory.url)

        return """
            References to this key are not updated: \
            \(from.path(percentEncoded: false)) becomes \(to.path(percentEncoded: false)). \
            Anything naming the old path — ssh_config, scripts, ssh-agent — keeps pointing at it.
            """
    }

    /// Executes the rename, restoring every file it has already moved if any move fails.
    func confirmRename() async {
        guard !operation.isInFlight,
              let pair = renamingPair,
              case .success(let newName) = renameOutcome
        else { return }

        operation = .renaming(pair.id)
        defer { operation = .idle }

        let plan = SSHKeyRenamePlan(pair: pair, newName: newName)
        var completed = 0

        do {
            for move in plan.moves {
                try await writer.move(from: move.from, to: move.to)
                completed += 1
            }
            renamingPair = nil
            renameProposal = ""
            notice = .renamed(newName)
        } catch {
            notice = await rollBack(plan, after: completed, reporting: error)
        }

        await refresh()
    }

    /// Undoes the moves that completed, and reports what the user is left with.
    ///
    /// A rollback that itself fails is the one outcome this feature cannot tidy away, so it
    /// names every path still out of place rather than reporting a clean failure the
    /// directory does not match.
    private func rollBack(
        _ plan: SSHKeyRenamePlan,
        after completed: Int,
        reporting failure: SSHKeyWriteError
    ) async -> KeyListNotice {
        var stranded: [String] = []

        for move in plan.inverse(ofCompleted: completed) {
            do {
                try await writer.move(from: move.from, to: move.to)
            } catch {
                stranded.append(move.from.lastPathComponent)
            }
        }

        guard !stranded.isEmpty else {
            return .failed(reason: "The rename did not happen. \(failure.reason)")
        }
        return .leftIncomplete(
            reason: """
                The rename could not be undone. \(failure.reason) \
                Still renamed: \(stranded.joined(separator: ", ")).
                """
        )
    }

    // MARK: - Deleting

    /// The confirmation's title. The words are this feature's; the gate is the design
    /// system's.
    func deletionTitle(for pair: SSHKeyPair) -> String {
        "Delete \(pair.displayName)?"
    }

    /// The confirmation's message, naming the pair and stating that the removal is final.
    func deletionMessage(for pair: SSHKeyPair) -> String {
        let files = pair.location.files.map(\.lastPathComponent).joined(separator: ", ")
        return """
            \(pair.displayName) and its files (\(files)) are removed permanently. \
            This cannot be undone — there is no Trash and no backup.
            """
    }

    /// Removes the pair's files. Called only once the user has confirmed; declining means
    /// this is never reached, and then nothing has been touched.
    func delete(_ pair: SSHKeyPair) async {
        guard !operation.isInFlight else { return }

        operation = .deleting(pair.id)
        defer { operation = .idle }

        var firstFailure: SSHKeyWriteError?
        var remaining: [String] = []

        for url in SSHKeyDeletePlan(pair: pair).removals {
            do {
                try await writer.remove(at: url)
            } catch {
                firstFailure = firstFailure ?? error
                remaining.append(url.lastPathComponent)
            }
        }

        if let firstFailure {
            notice = .leftIncomplete(
                reason: """
                    \(pair.displayName) was not fully deleted. \(firstFailure.reason) \
                    Still present: \(remaining.joined(separator: ", ")).
                    """
            )
        } else {
            notice = .deleted(pair.id)
        }

        await refresh()
    }
}
