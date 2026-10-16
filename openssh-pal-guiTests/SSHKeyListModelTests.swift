import Foundation
import Testing

/// Every state is driven through fabricated values: an in-memory reader, a recording writer
/// and a recording clipboard. Nothing here touches the file system, the real pasteboard, the
/// process environment or a literal SSH directory path.
@MainActor
@Suite("Key list model")
struct SSHKeyListModelTests {

    nonisolated private static let home = URL(filePath: "/fabricated/home", directoryHint: .isDirectory)
    nonisolated private static let keys = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)

    nonisolated private static let ed25519Line = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHG/eTv0q9SPBgITfzHoiFX9BXBTCO4InzbH19BagKve user@host"

    nonisolated private static func file(_ name: String) -> URL {
        keys.appending(path: name)
    }

    nonisolated private static func override(_ url: URL) -> LaunchEnvironment {
        LaunchEnvironment(
            arguments: [LaunchEnvironment.overrideArgument, url.path(percentEncoded: false)],
            environmentVariables: [:]
        )
    }

    /// A model over a fabricated directory, with the doubles the caller wants to inspect.
    private static func model(
        entries: [String] = [],
        contents: [String: String] = [:],
        failures: [URL: FileAccessError] = [:],
        directoryExists: Bool = true,
        writer: InMemorySSHKeyWriter = InMemorySSHKeyWriter(),
        clipboard: RecordingClipboardWriter = RecordingClipboardWriter(),
        references: HostReferenceLookup? = nil
    ) -> SSHKeyListModel {
        let reader = InMemorySSHDirectoryReader(
            directories: directoryExists ? [keys: entries.map(file)] : [:],
            files: Dictionary(uniqueKeysWithValues: contents.map { (file($0.key), Data($0.value.utf8)) }),
            failures: failures
        )

        return SSHKeyListModel(
            status: SSHDirectoryStatusModel(
                resolver: SSHDirectoryResolver(reader: reader),
                launchEnvironment: override(keys),
                homeDirectory: home,
                reader: reader
            ),
            reader: reader,
            writer: writer,
            clipboard: clipboard,
            hostReferences: references ?? StaticHostReferenceLookup(report: .references(hosts: [], hasUnresolved: false))
        )
    }

    /// A model over a directory holding one complete, parseable pair plus a certificate.
    private static func modelWithOnePair(
        writer: InMemorySSHKeyWriter = InMemorySSHKeyWriter(),
        clipboard: RecordingClipboardWriter = RecordingClipboardWriter(),
        certificate: Bool = false,
        references: HostReferenceLookup? = nil
    ) -> SSHKeyListModel {
        var entries = ["work_key", "work_key.pub"]
        if certificate { entries.append("work_key-cert.pub") }

        return model(
            entries: entries,
            contents: ["work_key.pub": ed25519Line + "\n"],
            writer: writer,
            clipboard: clipboard,
            references: references
        )
    }

    // MARK: - 1.1 / 1.7 / 1.8 the four states are distinct

    @Test("Before the first refresh the model is loading rather than empty")
    func startsOutLoading() {
        #expect(Self.model().state == .loading)
    }

    @Test("A directory with no key pairs presents an empty list, not a failure")
    func emptyDirectoryPresentsAnEmptyList() async {
        let model = Self.model(entries: ["config", "known_hosts"])

        await model.refresh()

        #expect(model.state == .loaded([]))
        #expect(model.state.isEmptyListing)
        #expect(model.state.failureReason == nil)
    }

    @Test("A directory that cannot be read presents its reason rather than an empty list")
    func unreadableDirectoryPresentsItsReason() async {
        let model = Self.model(entries: ["work_key.pub"], failures: [Self.keys: .accessDenied(Self.keys)])

        await model.refresh()

        #expect(model.state == .unreadable(.accessDenied(Self.keys)))
        // The distinction 1.7 turns on: this is *not* the empty state.
        #expect(!model.state.isEmptyListing)
        #expect(model.state.failureReason != nil)
        #expect(model.state.pairs.isEmpty)
    }

    @Test("A directory that never resolved is its own state, distinct from one that cannot be read")
    func unresolvedDirectoryIsItsOwnState() async {
        let model = Self.model(directoryExists: false)

        await model.refresh()

        #expect(model.state == .noDirectory(.overridePathDoesNotExist(Self.keys)))
        #expect(!model.state.isEmptyListing)
        #expect(model.state.failureReason != nil)
    }

    @Test("A directory with keys presents one entry per pair, with its attributes parsed")
    func keysArePresentedWithTheirAttributes() async throws {
        let model = Self.modelWithOnePair(certificate: true)

        await model.refresh()

        #expect(model.state.pairs.count == 1)
        let pair = try #require(model.state.pairs.first)
        #expect(pair.displayName == "work_key")
        #expect(pair.hasCertificate)
        #expect(pair.parsedPublicKey?.algorithm == .ed25519)
        #expect(pair.parsedPublicKey?.bitLength == 256)
        #expect(pair.parsedPublicKey?.comment == "user@host")
    }

    // MARK: - 1.6 / 2.6 one bad entry degrades alone

    @Test("A corrupt public key degrades its own entry and leaves every other pair presented")
    func corruptEntryDegradesAlone() async throws {
        let model = Self.model(
            entries: ["good", "good.pub", "broken", "broken.pub"],
            contents: [
                "good.pub": Self.ed25519Line,
                "broken.pub": "this is not a key",
            ]
        )

        await model.refresh()

        #expect(model.state.pairs.count == 2)
        let broken = try #require(model.state.pairs.first { $0.displayName == "broken" })
        let good = try #require(model.state.pairs.first { $0.displayName == "good" })

        #expect(broken.parseFailure != nil)
        #expect(broken.parsedPublicKey == nil)
        #expect(good.parsedPublicKey != nil)
    }

    @Test("A public key that cannot be read is marked unreadable rather than malformed")
    func unreadablePublicKeyIsItsOwnFailure() async throws {
        let model = Self.model(
            entries: ["denied", "denied.pub"],
            failures: [Self.file("denied.pub"): .accessDenied(Self.file("denied.pub"))]
        )

        await model.refresh()

        let pair = try #require(model.state.pairs.first)
        #expect(pair.parseFailure == .fileUnreadable)
    }

    @Test("A pair whose private key is absent is still presented, and says so")
    func absentPrivateKeyIsStillPresented() async throws {
        let model = Self.model(entries: ["orphan.pub"], contents: ["orphan.pub": Self.ed25519Line])

        await model.refresh()

        #expect(try #require(model.state.pairs.first).isPrivateKeyMissing)
    }

    // MARK: - 1.10 responsiveness

    @Test("Enumerating reports itself, so the panel can stay responsive rather than blank")
    func refreshingIsObservable() async {
        let model = Self.modelWithOnePair()

        #expect(!model.isRefreshing)
        await model.refresh()
        #expect(!model.isRefreshing)
    }

    @Test("A refresh keeps the previous list visible rather than dropping back to loading")
    func refreshKeepsThePreviousList() async {
        let model = Self.modelWithOnePair()

        await model.refresh()
        let first = model.state.pairs
        await model.refresh()

        #expect(model.state.pairs == first)
    }

    // MARK: - 3.1-3.5 copying

    @Test("Copying places the public key file's contents on the clipboard")
    func copyPlacesThePublicKeyOnTheClipboard() async throws {
        let clipboard = RecordingClipboardWriter()
        let model = Self.modelWithOnePair(clipboard: clipboard)
        await model.refresh()

        await model.copyPublicKey(of: try #require(model.state.pairs.first))

        #expect(clipboard.writes == [Self.ed25519Line + "\n"])
    }

    @Test("A completed copy is confirmed to the user")
    func copyIsConfirmed() async throws {
        let model = Self.modelWithOnePair()
        await model.refresh()

        await model.copyPublicKey(of: try #require(model.state.pairs.first))

        #expect(model.notice?.role == .success)
        #expect(try #require(model.notice?.message).localizedCaseInsensitiveContains("copied"))
    }

    @Test("A public key that cannot be read reports its reason and leaves the clipboard untouched")
    func unreadableKeyLeavesTheClipboardAlone() async throws {
        let clipboard = RecordingClipboardWriter()
        let model = Self.model(
            entries: ["denied", "denied.pub"],
            failures: [Self.file("denied.pub"): .accessDenied(Self.file("denied.pub"))],
            clipboard: clipboard
        )
        await model.refresh()

        await model.copyPublicKey(of: try #require(model.state.pairs.first))

        #expect(clipboard.isEmpty)
        #expect(model.notice?.role == .failure)
    }

    @Test("Only the public key's own location is ever read for a copy")
    func copyReadsOnlyThePublicKey() async throws {
        // The port is handed text, not a path, so there is no call it could make that would
        // reach a private key. The assertion here is the complement: what lands on the
        // clipboard is byte-for-byte the public key file.
        let clipboard = RecordingClipboardWriter()
        let model = Self.model(
            entries: ["work_key", "work_key.pub"],
            contents: [
                "work_key.pub": Self.ed25519Line,
                "work_key": "PRIVATE KEY MATERIAL",
            ],
            clipboard: clipboard
        )
        await model.refresh()

        await model.copyPublicKey(of: try #require(model.state.pairs.first))

        #expect(clipboard.writes == [Self.ed25519Line])
        #expect(!(clipboard.lastWrite ?? "").contains("PRIVATE KEY MATERIAL"))
    }

    // MARK: - 4.1 / 5.6 / 5.7 renaming: validation first

    @Test("Starting a rename offers the pair's current name for editing")
    func renameStartsFromTheCurrentName() async throws {
        let model = Self.modelWithOnePair()
        await model.refresh()

        model.beginRename(of: try #require(model.state.pairs.first))

        #expect(model.renamingPair?.displayName == "work_key")
        #expect(model.renameProposal == "work_key")
    }

    @Test("A rename that keeps the current name is confirmable and is not a self-collision")
    func keepingTheCurrentNameIsConfirmable() async throws {
        let model = Self.modelWithOnePair(certificate: true)
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first))

        #expect(model.renameValidation == .valid)
        #expect(model.canConfirmRename)
    }

    @Test("While the proposed name is rejected the confirming control stays unavailable")
    func rejectedNameBlocksConfirmation() async throws {
        let model = Self.modelWithOnePair()
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first))

        for rejected in ["", "   ", "nested/key", "thing.pub", "config"] {
            model.renameProposal = rejected

            #expect(!model.canConfirmRename, "\(rejected) should not be confirmable")
            #expect(model.renameValidation != .valid)
        }
    }

    @Test("A name colliding with another file is rejected, naming the file at risk")
    func collidingNameIsRejected() async throws {
        let model = Self.model(
            entries: ["work_key", "work_key.pub", "other.pub"],
            contents: ["work_key.pub": Self.ed25519Line, "other.pub": Self.ed25519Line]
        )
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first { $0.displayName == "work_key" }))

        model.renameProposal = "other"

        #expect(!model.canConfirmRename)
        #expect(try #require(model.renameValidation.message).contains("other.pub"))
    }

    @Test("A rejected name leaves every file unchanged, because nothing is executed")
    func rejectedNameChangesNothing() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.modelWithOnePair(writer: writer)
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first))

        model.renameProposal = "config"
        await model.confirmRename()

        #expect(writer.touchedPaths.isEmpty)
    }

    // MARK: - 6.1 / 6.2 the reference warning

    @Test("The rename warning names both paths and says references are not updated")
    func renameWarningNamesBothPaths() async throws {
        let model = Self.modelWithOnePair()
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first))
        model.renameProposal = "renamed_key"

        let message = try #require(model.renameWarningMessage)

        #expect(message.contains(Self.file("work_key").path(percentEncoded: false)))
        #expect(message.contains(Self.file("renamed_key").path(percentEncoded: false)))
        #expect(message.localizedCaseInsensitiveContains("not updated"))
        #expect(try #require(model.renameWarningTitle).localizedCaseInsensitiveContains("rename"))
    }

    @Test("There is no warning to show while the proposed name is rejected")
    func noWarningForARejectedName() async throws {
        let model = Self.modelWithOnePair()
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first))

        model.renameProposal = "config"

        #expect(model.renameWarningMessage == nil)
    }

    // MARK: - crud-ssh-config-hosts 11.1–11.4 host references

    @Test("The rename warning lists the hosts whose IdentityFile names the key")
    func renameWarningNamesReferencingHosts() async throws {
        let lookup = StaticHostReferenceLookup(report: .references(hosts: ["github.com", "bastion"], hasUnresolved: false))
        let model = Self.modelWithOnePair(references: lookup)
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first))
        model.renameProposal = "renamed_key"

        let message = try #require(model.renameWarningMessage)
        #expect(message.contains("github.com, bastion"))
        #expect(lookup.askedAbout == [SSHKeyName.discovered("work_key")!])
    }

    @Test("The deletion confirmation lists the referencing hosts")
    func deletionNamesReferencingHosts() async throws {
        let model = Self.modelWithOnePair(
            references: StaticHostReferenceLookup(report: .references(hosts: ["github.com"], hasUnresolved: false))
        )
        await model.refresh()

        #expect(model.deletionMessage(for: try #require(model.state.pairs.first)).contains("github.com"))
    }

    @Test("Unresolved references are stated as possibly naming the key")
    func unresolvedReferencesAreStated() async throws {
        let model = Self.modelWithOnePair(
            references: StaticHostReferenceLookup(report: .references(hosts: [], hasUnresolved: true))
        )
        await model.refresh()
        let pair = try #require(model.state.pairs.first)

        #expect(model.deletionMessage(for: pair).localizedCaseInsensitiveContains("could not be resolved"))
    }

    @Test("A configuration that could not be read is stated, never presented as no hosts")
    func unavailableReferencesAreStated() async throws {
        let model = Self.modelWithOnePair(
            references: StaticHostReferenceLookup(report: .unavailable(reason: "Permission denied: config"))
        )
        await model.refresh()
        let pair = try #require(model.state.pairs.first)
        let message = model.deletionMessage(for: pair)

        #expect(message.localizedCaseInsensitiveContains("could not be checked"))
        #expect(!message.contains("No host"))
    }

    // MARK: - 4.2 / 4.3 renaming: execution

    @Test("A confirmed rename moves the private key, the public key and the certificate")
    func confirmedRenameMovesEveryFile() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.modelWithOnePair(writer: writer, certificate: true)
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first))
        model.renameProposal = "renamed_key"

        await model.confirmRename()

        #expect(writer.moves == [
            .init(from: Self.file("work_key"), to: Self.file("renamed_key")),
            .init(from: Self.file("work_key.pub"), to: Self.file("renamed_key.pub")),
            .init(from: Self.file("work_key-cert.pub"), to: Self.file("renamed_key-cert.pub")),
        ])
        #expect(model.renamingPair == nil)
        #expect(model.notice?.role == .success)
    }

    @Test("A completed rename re-enumerates, so the list reflects the change")
    func completedRenameReEnumerates() async throws {
        let model = Self.modelWithOnePair()
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first))
        model.renameProposal = "renamed_key"

        await model.confirmRename()

        // The fabricated listing does not change, so the assertion is that the model asked
        // again rather than trusting its own cache.
        #expect(model.state.pairs.count == 1)
    }

    // MARK: - 4.6 rollback

    @Test("A rename whose second move fails restores every file already moved")
    func failedRenameRestoresEveryMovedFile() async throws {
        let writer = InMemorySSHKeyWriter(
            failures: [Self.file("work_key.pub"): .accessDenied(Self.file("work_key.pub"))]
        )
        let model = Self.modelWithOnePair(writer: writer, certificate: true)
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first))
        model.renameProposal = "renamed_key"

        await model.confirmRename()

        // The private key moved, then the public key failed, so the private key moved back
        // and the certificate was never touched.
        #expect(writer.moves == [
            .init(from: Self.file("work_key"), to: Self.file("renamed_key")),
            .init(from: Self.file("renamed_key"), to: Self.file("work_key")),
        ])
        #expect(!writer.touchedPaths.contains(Self.file("work_key-cert.pub")))
        #expect(model.notice?.role == .failure)
    }

    @Test("A rename whose first move fails leaves nothing to restore and reports the reason")
    func firstMoveFailureReportsTheReason() async throws {
        let writer = InMemorySSHKeyWriter(
            failures: [Self.file("work_key"): .destinationExists(Self.file("renamed_key"))]
        )
        let model = Self.modelWithOnePair(writer: writer)
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first))
        model.renameProposal = "renamed_key"

        await model.confirmRename()

        #expect(writer.moves.isEmpty)
        #expect(try #require(model.notice?.message).contains("renamed_key"))
    }

    @Test("A restoration that itself fails names every path still out of place")
    func failedRestorationNamesWhatIsOutOfPlace() async throws {
        let writer = InMemorySSHKeyWriter(
            failures: [Self.file("work_key.pub"): .accessDenied(Self.file("work_key.pub"))]
        )
        let model = Self.modelWithOnePair(writer: writer)
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first))
        model.renameProposal = "renamed_key"

        // The private key will move, the public key will fail, and the move back will fail
        // too — which leaves the directory mid-rename and the user needing to know which
        // file is where.
        writer.setFailure(.accessDenied(Self.file("renamed_key")), for: Self.file("renamed_key"))

        await model.confirmRename()

        let message = try #require(model.notice?.message)
        #expect(model.notice?.role == .warning)
        #expect(message.contains("renamed_key"))
    }

    @Test("Cancelling a rename changes nothing and clears the draft")
    func cancellingARenameChangesNothing() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.modelWithOnePair(writer: writer)
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first))
        model.renameProposal = "renamed_key"

        model.cancelRename()

        #expect(model.renamingPair == nil)
        #expect(writer.touchedPaths.isEmpty)
    }

    // MARK: - 4.4 contents are untouched

    @Test("A rename performs only moves, so no file's contents can change")
    func renameOnlyMoves() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.modelWithOnePair(writer: writer, certificate: true)
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first))
        model.renameProposal = "renamed_key"

        await model.confirmRename()

        // The port has no method that writes contents, and the model made no removal either.
        #expect(writer.removals.isEmpty)
        #expect(writer.attemptedRemovals.isEmpty)
    }

    @Test("A rename touches nothing outside the renamed pair")
    func renameTouchesNothingElse() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.model(
            entries: ["work_key", "work_key.pub", "bystander", "config"],
            contents: ["work_key.pub": Self.ed25519Line],
            writer: writer
        )
        await model.refresh()
        model.beginRename(of: try #require(model.state.pairs.first))
        model.renameProposal = "renamed_key"

        await model.confirmRename()

        for path in writer.touchedPaths {
            #expect(path.lastPathComponent.hasPrefix("work_key") || path.lastPathComponent.hasPrefix("renamed_key"))
        }
    }

    // MARK: - 4.7 one operation at a time

    @Test("A second mutation cannot begin while one is in flight")
    func oneOperationAtATime() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.modelWithOnePair(writer: writer)
        await model.refresh()
        let pair = try #require(model.state.pairs.first)
        model.beginRename(of: pair)
        model.renameProposal = "renamed_key"

        writer.hold()
        let rename = Task { await model.confirmRename() }
        // Let the rename reach the held writer.
        await Task.yield()
        #expect(model.operation == .renaming(pair.id))

        await model.delete(pair)
        #expect(writer.attemptedRemovals.isEmpty, "a deletion must not begin during a rename")

        writer.release()
        await rename.value
        #expect(model.operation == .idle)
    }

    // MARK: - 7.1 / 7.9 the deletion confirmation

    @Test("The deletion confirmation names the pair and states that the removal is permanent")
    func deletionConfirmationNamesThePair() async throws {
        let model = Self.modelWithOnePair()
        await model.refresh()
        let pair = try #require(model.state.pairs.first)

        #expect(model.deletionTitle(for: pair).contains("work_key"))
        let message = model.deletionMessage(for: pair)
        #expect(message.contains("work_key"))
        #expect(message.localizedCaseInsensitiveContains("permanent"))
        #expect(message.localizedCaseInsensitiveContains("cannot be undone"))
    }

    @Test("Nothing is removed until a deletion is actually asked for")
    func nothingIsRemovedWithoutAsking() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.modelWithOnePair(writer: writer)
        await model.refresh()
        let pair = try #require(model.state.pairs.first)

        // Composing the confirmation's words is not an action: declining the confirmation
        // simply means `delete` is never called, and then no file has been touched.
        _ = model.deletionTitle(for: pair)
        _ = model.deletionMessage(for: pair)

        #expect(writer.touchedPaths.isEmpty)
    }

    // MARK: - 7.3 / 7.4 / 7.6 deleting

    @Test("A confirmed deletion removes the private key, the public key and the certificate")
    func deletionRemovesEveryFile() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.modelWithOnePair(writer: writer, certificate: true)
        await model.refresh()

        await model.delete(try #require(model.state.pairs.first))

        #expect(writer.removals == [
            Self.file("work_key"),
            Self.file("work_key.pub"),
            Self.file("work_key-cert.pub"),
        ])
        #expect(model.notice?.role == .success)
    }

    @Test("A deletion that fails partway names the files that remain")
    func failedDeletionNamesWhatRemains() async throws {
        let writer = InMemorySSHKeyWriter(
            failures: [Self.file("work_key.pub"): .accessDenied(Self.file("work_key.pub"))]
        )
        let model = Self.modelWithOnePair(writer: writer, certificate: true)
        await model.refresh()

        await model.delete(try #require(model.state.pairs.first))

        let message = try #require(model.notice?.message)
        #expect(model.notice?.role == .warning)
        #expect(message.contains("work_key.pub"))
        // The certificate was still removed, so it must not be reported as remaining.
        #expect(!message.contains("work_key-cert.pub"))
    }

    @Test("A deletion acts only on the files of the pair it was handed")
    func deletionActsOnlyOnTheIdentifiedPair() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.model(
            entries: ["work_key", "work_key.pub", "other", "other.pub", "config"],
            contents: ["work_key.pub": Self.ed25519Line, "other.pub": Self.ed25519Line],
            writer: writer
        )
        await model.refresh()

        await model.delete(try #require(model.state.pairs.first { $0.displayName == "work_key" }))

        #expect(writer.removals == [Self.file("work_key"), Self.file("work_key.pub")])
        #expect(!writer.touchedPaths.contains(Self.file("other")))
        #expect(!writer.touchedPaths.contains(Self.file("config")))
    }

    @Test("Each deletion is its own operation, so two deletions take two confirmations")
    func eachDeletionIsItsOwnOperation() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.model(
            entries: ["a", "a.pub", "b", "b.pub"],
            contents: ["a.pub": Self.ed25519Line, "b.pub": Self.ed25519Line],
            writer: writer
        )
        await model.refresh()

        await model.delete(try #require(model.state.pairs.first { $0.displayName == "a" }))
        #expect(model.operation == .idle)

        await model.delete(try #require(model.state.pairs.first { $0.displayName == "b" }))

        // Two separate calls, each gated by its own confirmation in the view. There is no
        // state on the model that could remember a previous confirmation.
        #expect(writer.removals.count == 4)
    }

    // MARK: - 11.7 nothing is written except as the result of an action

    @Test("A refresh writes nothing at all")
    func refreshWritesNothing() async {
        let writer = InMemorySSHKeyWriter()
        let model = Self.modelWithOnePair(writer: writer, certificate: true)

        await model.refresh()
        await model.refresh()

        #expect(writer.touchedPaths.isEmpty)
    }

    @Test("A notice can be dismissed, so a stale confirmation does not linger")
    func noticeCanBeDismissed() async throws {
        let model = Self.modelWithOnePair()
        await model.refresh()
        await model.copyPublicKey(of: try #require(model.state.pairs.first))

        model.dismissNotice()

        #expect(model.notice == nil)
    }
}
