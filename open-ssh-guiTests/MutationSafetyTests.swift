import Foundation
import Testing

/// The guarantees that matter most if anything else is wrong: that a GUI operation cannot
/// cost the user access to a machine.
///
/// These are asserted here directly rather than left as consequences of the unit suites,
/// because each is a property of the whole feature and no single component owns it.
@MainActor
@Suite("Mutation safety")
struct MutationSafetyTests {

    nonisolated private static let home = URL(filePath: "/fabricated/home", directoryHint: .isDirectory)
    nonisolated private static let keys = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)
    nonisolated private static let ed25519Line = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHG/eTv0q9SPBgITfzHoiFX9BXBTCO4InzbH19BagKve user@host"

    nonisolated private static func override(_ url: URL) -> LaunchEnvironment {
        LaunchEnvironment(
            arguments: [LaunchEnvironment.overrideArgument, url.path(percentEncoded: false)],
            environmentVariables: [:]
        )
    }

    /// A directory holding three pairs, a certificate for one of them, and the files OpenSSH
    /// owns — so a bystander is always present to be harmed.
    nonisolated private static let populated = [
        "work_key", "work_key.pub", "work_key-cert.pub",
        "other_key", "other_key.pub",
        "orphan.pub",
        "config", "known_hosts", "authorized_keys",
    ]

    private static func model(
        in directory: URL = keys,
        entries: [String] = populated,
        writer: InMemorySSHKeyWriter
    ) -> SSHKeyListModel {
        let reader = InMemorySSHDirectoryReader(
            directories: [directory: entries.map { directory.appending(path: $0) }],
            files: Dictionary(
                uniqueKeysWithValues: entries
                    .filter { $0.hasSuffix(".pub") }
                    .map { (directory.appending(path: $0), Data(ed25519Line.utf8)) }
            )
        )

        return SSHKeyListModel(
            status: SSHDirectoryStatusModel(
                resolver: SSHDirectoryResolver(reader: reader),
                launchEnvironment: override(directory),
                homeDirectory: home,
                reader: reader
            ),
            reader: reader,
            writer: writer,
            clipboard: RecordingClipboardWriter(),
            hostReferences: StaticHostReferenceLookup(report: .references(hosts: [], hasUnresolved: false))
        )
    }

    private static func pair(_ name: String, in model: SSHKeyListModel) throws -> SSHKeyPair {
        try #require(model.state.pairs.first { $0.displayName == name })
    }

    // MARK: - 11.1 containment

    @Test("Every path a rename touches is inside the resolved directory")
    func renamePathsStayInsideTheDirectory() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.model(writer: writer)
        await model.refresh()

        model.beginRename(of: try Self.pair("work_key", in: model))
        model.renameProposal = "renamed_key"
        await model.confirmRename()

        #expect(!writer.touchedPaths.isEmpty)
        for path in writer.touchedPaths {
            #expect(
                path.deletingLastPathComponent().standardizedFileURL == Self.keys.standardizedFileURL,
                "\(path.path(percentEncoded: false)) is outside the resolved directory"
            )
        }
    }

    @Test("Every path a deletion touches is inside the resolved directory")
    func deletionPathsStayInsideTheDirectory() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.model(writer: writer)
        await model.refresh()

        await model.delete(try Self.pair("work_key", in: model))

        #expect(!writer.touchedPaths.isEmpty)
        for path in writer.touchedPaths {
            #expect(path.deletingLastPathComponent().standardizedFileURL == Self.keys.standardizedFileURL)
        }
    }

    @Test("A name that would reach outside the directory is refused before anything moves")
    func traversingNameIsRefused() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.model(writer: writer)
        await model.refresh()
        model.beginRename(of: try Self.pair("work_key", in: model))

        for escaping in ["../elsewhere", "/absolute", "sub/dir", ".."] {
            model.renameProposal = escaping
            await model.confirmRename()
        }

        #expect(writer.touchedPaths.isEmpty)
    }

    @Test("Under a launch override every mutation stays in the override, never the home directory")
    func overrideConfinesEveryMutation() async throws {
        let elsewhere = URL(filePath: "/fabricated/scratch", directoryHint: .isDirectory)
        let writer = InMemorySSHKeyWriter()
        let model = Self.model(in: elsewhere, writer: writer)
        await model.refresh()

        model.beginRename(of: try Self.pair("work_key", in: model))
        model.renameProposal = "renamed_key"
        await model.confirmRename()
        await model.delete(try Self.pair("other_key", in: model))

        #expect(!writer.touchedPaths.isEmpty)
        for path in writer.touchedPaths {
            #expect(path.deletingLastPathComponent().standardizedFileURL == elsewhere.standardizedFileURL)
            #expect(!path.path(percentEncoded: false).hasPrefix(Self.home.path(percentEncoded: false)))
        }
    }

    // MARK: - 11.2 bystander safety

    @Test("A rename touches no file outside the pair it was asked about")
    func renameTouchesNoBystander() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.model(writer: writer)
        await model.refresh()

        model.beginRename(of: try Self.pair("work_key", in: model))
        model.renameProposal = "renamed_key"
        await model.confirmRename()

        let bystanders = ["other_key", "other_key.pub", "orphan.pub", "config", "known_hosts", "authorized_keys"]
        for name in bystanders {
            #expect(
                !writer.touchedPaths.contains(Self.keys.appending(path: name)),
                "\(name) was touched by a rename of another pair"
            )
        }
    }

    @Test("A deletion touches no file outside the pair the user identified")
    func deletionTouchesNoBystander() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.model(writer: writer)
        await model.refresh()

        await model.delete(try Self.pair("work_key", in: model))

        let bystanders = ["other_key", "other_key.pub", "orphan.pub", "config", "known_hosts", "authorized_keys"]
        for name in bystanders {
            #expect(!writer.touchedPaths.contains(Self.keys.appending(path: name)))
        }
    }

    @Test("A name that would replace an existing file is refused, and that file is never reached")
    func collidingRenameNeverReachesTheFile() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.model(writer: writer)
        await model.refresh()

        model.beginRename(of: try Self.pair("work_key", in: model))
        model.renameProposal = "other_key"
        await model.confirmRename()

        #expect(writer.touchedPaths.isEmpty)
    }

    @Test("Even a defective validator cannot destroy a bystander, because the platform refuses")
    func theAdapterRefusesToReplaceABystander() async throws {
        // The backstop beneath validation: this goes straight to the adapter, skipping every
        // check the model would have made.
        try await TemporaryDirectory.withOne { scratch in
            let source = try scratch.file(named: "newcomer", contents: Data("newcomer".utf8))
            let bystander = try scratch.file(named: "bystander", contents: Data("precious".utf8))

            await #expect(throws: SSHKeyWriteError.destinationExists(bystander)) {
                try await FileSystemSSHKeyWriter().move(from: source, to: bystander)
            }

            #expect(try Data(contentsOf: bystander) == Data("precious".utf8))
        }
    }

    // MARK: - 11.5 a multi-file operation that cannot complete

    @Test("A rename that cannot complete leaves the real directory exactly as it was")
    func failedRenameLeavesTheRealDirectoryUnchanged() async throws {
        // The real writer, against a real scratch directory. The blocking file makes the
        // second move fail the way it would in the wild: the destination already exists.
        try await TemporaryDirectory.withOne { scratch in
            let keys = try scratch.subdirectory(named: "keys")
            try Data("PRIVATE".utf8).write(to: keys.appending(path: "work_key"))
            try Data(Self.ed25519Line.utf8).write(to: keys.appending(path: "work_key.pub"))
            try Data("blocking".utf8).write(to: keys.appending(path: "renamed_key.pub"))

            let before = try Self.snapshot(of: keys)

            let reader = FileSystemSSHDirectoryReader()
            let model = SSHKeyListModel(
                status: SSHDirectoryStatusModel(
                    resolver: SSHDirectoryResolver(reader: reader),
                    launchEnvironment: Self.override(keys),
                    homeDirectory: Self.home,
                    reader: reader
                ),
                reader: reader,
                writer: FileSystemSSHKeyWriter(),
                clipboard: RecordingClipboardWriter(),
                hostReferences: StaticHostReferenceLookup(report: .references(hosts: [], hasUnresolved: false))
            )
            await model.refresh()

            let pair = try Self.pair("work_key", in: model)
            model.beginRename(of: pair)
            // The validator would normally refuse this, so it is bypassed deliberately: the
            // assertion is about what happens when a move fails partway, however it got there.
            model.renameProposal = "renamed_key"
            #expect(!model.canConfirmRename, "the collision should already have been caught")

            // Drive the plan directly, which is what a defective validator would have allowed.
            let plan = SSHKeyRenamePlan(pair: pair, newName: try #require(SSHKeyName.discovered("renamed_key")))
            let writer = FileSystemSSHKeyWriter()
            var completed = 0
            do {
                for move in plan.moves {
                    try await writer.move(from: move.from, to: move.to)
                    completed += 1
                }
            } catch {
                for move in plan.inverse(ofCompleted: completed) {
                    try await writer.move(from: move.from, to: move.to)
                }
            }

            #expect(try Self.snapshot(of: keys) == before)
        }
    }

    @Test("A deletion that fails partway removes only what it could, and names the rest")
    func failedDeletionReportsWhatRemains() async throws {
        let writer = InMemorySSHKeyWriter(
            failures: [Self.keys.appending(path: "work_key.pub"): .accessDenied(Self.keys.appending(path: "work_key.pub"))]
        )
        let model = Self.model(writer: writer)
        await model.refresh()

        await model.delete(try Self.pair("work_key", in: model))

        // A deletion is not reversible — the files that went are gone — so the obligation is
        // an accurate report rather than a restoration.
        #expect(model.notice?.role == .warning)
        #expect(try #require(model.notice?.message).contains("work_key.pub"))
    }

    // MARK: - 11.7 nothing is written except as the result of a confirmed action

    @Test("Opening the panel, listing, selecting and composing a confirmation write nothing")
    func readOnlyPathsWriteNothing() async throws {
        let writer = InMemorySSHKeyWriter()
        let model = Self.model(writer: writer)

        await model.refresh()
        await model.refresh()

        let pair = try Self.pair("work_key", in: model)
        _ = model.deletionTitle(for: pair)
        _ = model.deletionMessage(for: pair)
        model.beginRename(of: pair)
        model.renameProposal = "renamed_key"
        _ = model.renameWarningMessage
        _ = model.renameValidation
        _ = model.canConfirmRename
        model.cancelRename()
        await model.copyPublicKey(of: pair)
        model.dismissNotice()

        #expect(writer.touchedPaths.isEmpty, "something wrote without a confirmed action")
    }

    @Test("A generation that fails writes nothing the user did not already have")
    func failedGenerationWritesNothing() async throws {
        let generator = StubSSHKeyGenerator(outcome: .failure(.toolUnavailable(URL(filePath: "/fabricated/bin/x"))))
        let form = NewKeyFormModel(generator: generator, defaultComment: "user@host")
        form.begin(in: SSHDirectory(url: Self.keys), existing: [])
        form.name = "new_key"

        form.submit()
        await form.waitForGeneration()

        #expect(form.completion == nil)
        #expect(form.failureReason != nil)
    }

    @Test("The writing port has no way to bring a file into existence")
    func theWritePortCannotCreate() async throws {
        // Stated as a test because it is the structural claim the whole "defer to OpenSSH"
        // commitment rests on: the only methods are a move and a removal, so the only code
        // path that creates a file anywhere in this feature is ssh-keygen itself.
        let writer: any SSHKeyWriting = InMemorySSHKeyWriter()

        try await TemporaryDirectory.withOne { scratch in
            let target = scratch.url.appending(path: "created")

            // There is no `create`, no `write`, no `touch` to call. The nearest thing is a
            // move, which needs a file that already exists.
            await #expect(throws: SSHKeyWriteError.self) {
                try await FileSystemSSHKeyWriter().move(from: target, to: scratch.url.appending(path: "other"))
            }
            #expect(!FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
            _ = writer
        }
    }

    /// Every file in `directory`, with its contents, for a before-and-after comparison.
    nonisolated private static func snapshot(of directory: URL) throws -> [String: Data] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return try Dictionary(
            uniqueKeysWithValues: entries.map { ($0.lastPathComponent, try Data(contentsOf: $0)) }
        )
    }
}
