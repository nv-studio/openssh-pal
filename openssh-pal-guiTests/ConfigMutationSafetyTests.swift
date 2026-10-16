import Foundation
import Testing

/// The guarantees that matter most if anything else about configuration writing is wrong: a
/// damaged `config` can cost the user access to every machine it describes.
///
/// Asserted here directly rather than left as consequences of the unit suites, because each is
/// a property of the whole feature and no single component owns it.
@MainActor
@Suite("Configuration mutation safety")
struct ConfigMutationSafetyTests {

    nonisolated private static let home = URL(filePath: "/fabricated/home", directoryHint: .isDirectory)
    nonisolated private static let keys = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)

    nonisolated private static func file(_ name: String) -> URL { keys.appending(path: name) }

    nonisolated private static func override(_ url: URL) -> LaunchEnvironment {
        LaunchEnvironment(
            arguments: [LaunchEnvironment.overrideArgument, url.path(percentEncoded: false)],
            environmentVariables: [:]
        )
    }

    private struct Harness {
        let configuration: SSHConfigModel
        let keyList: SSHKeyListModel
        let form: HostFormModel
        let writer: InMemorySSHConfigWriter
        let keyWriter: InMemorySSHKeyWriter
        let auditor: AuditingSSHDirectoryReader
    }

    /// A populated override directory: an included file, a key pair, and includes that point
    /// outside the directory — so there is always somewhere a write must not go.
    private static func harness() async -> Harness {
        let files: [String: String] = [
            "config": """
                Include config.d/*
                Include ~/outside
                Include /fabricated/elsewhere/config

                Host bastion
                    HostName bastion.example.com
                    IdentityFile /fabricated/keys/id_work

                Host *
                    ServerAliveInterval 30

                """,
            "config.d/work": "Host work\n    User w\n",
            "id_work.pub": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHG/eTv0q9SPBgITfzHoiFX9BXBTCO4InzbH19BagKve user@host\n",
            "id_work": "",
        ]
        let data = Dictionary(uniqueKeysWithValues: files.map { (file($0.key), Data($0.value.utf8)) })
        let configData = data.filter { !$0.key.lastPathComponent.hasPrefix("id_") }
        let subdirectory = keys.appending(path: "config.d", directoryHint: .isDirectory)

        let writer = InMemorySSHConfigWriter(files: configData)
        let base = InMemorySSHDirectoryReader(
            directories: [
                keys: ["config", "id_work", "id_work.pub"].map(file) + [subdirectory],
                subdirectory: [subdirectory.appending(path: "work")],
            ],
            files: data
        )
        let auditor = AuditingSSHDirectoryReader(wrapping: WriterBackedSSHDirectoryReader(base: base, writer: writer))
        let status = SSHDirectoryStatusModel(
            resolver: SSHDirectoryResolver(reader: auditor),
            launchEnvironment: override(keys),
            homeDirectory: home,
            reader: auditor
        )
        let configuration = SSHConfigModel(status: status, reader: auditor, writer: writer, homeDirectory: home, userName: "alice")
        let keyWriter = InMemorySSHKeyWriter()
        let keyList = SSHKeyListModel(
            status: status,
            reader: auditor,
            writer: keyWriter,
            clipboard: RecordingClipboardWriter(),
            hostReferences: configuration
        )

        await configuration.refresh()
        await keyList.refresh()

        return Harness(
            configuration: configuration,
            keyList: keyList,
            form: HostFormModel(configuration: configuration, keys: keyList),
            writer: writer,
            keyWriter: keyWriter,
            auditor: auditor
        )
    }

    private static func isInside(_ url: URL, _ directory: URL) -> Bool {
        url.standardizedFileURL.path(percentEncoded: false).hasPrefix(directory.standardizedFileURL.path(percentEncoded: false))
    }

    private static func entry(_ name: String, in harness: Harness) throws -> HostEntry {
        try #require(harness.configuration.entries.first { $0.displayName == name })
    }

    // MARK: - 9.8 / 9.9 / 9.10 write scope

    @Test("Every path a create, an edit and a deletion touch lies inside the override directory")
    func everyWriteStaysInside() async throws {
        let harness = await Self.harness()

        harness.form.beginCreate()
        harness.form.draft.patterns = "new"
        await harness.form.submit()

        harness.form.beginEdit(try Self.entry("work", in: harness))
        harness.form.draft.user = "changed"
        await harness.form.submit()

        _ = await harness.configuration.delete(try Self.entry("bastion", in: harness))

        #expect(harness.writer.completedWriteCount > 0)
        for path in harness.writer.touchedPaths {
            #expect(Self.isInside(path, Self.keys), "wrote outside the directory: \(path)")
        }
    }

    @Test("Under an override nothing outside it is read, and the home directory is never reached")
    func overrideConfinesReading() async throws {
        let harness = await Self.harness()

        let skipped = harness.configuration.configuration?.issues.filter {
            if case .skippedInclude(_, _, _, .outsideOverride) = $0 { return true }
            return false
        }
        #expect(skipped?.count == 2)

        for path in harness.auditor.allPaths {
            #expect(Self.isInside(path, Self.keys), "read outside the override: \(path)")
            #expect(!Self.isInside(path, Self.home), "reached the home directory: \(path)")
        }
    }

    @Test("Each write changes only the file that declares the affected block")
    func writesOnlyTheDeclaringFile() async throws {
        let harness = await Self.harness()

        harness.form.beginEdit(try Self.entry("work", in: harness))
        harness.form.draft.hostName = "w.example.com"
        await harness.form.submit()

        let replaced = harness.writer.calls.compactMap { call -> URL? in
            if case .replace(let url) = call { return url }
            return nil
        }
        #expect(replaced == [Self.keys.appending(path: "config.d/work")])
    }

    // MARK: - 9.12 nothing without a confirmed action

    @Test("Opening, listing, selecting, composing and cancelling write nothing")
    func nothingIsWrittenWithoutAConfirmedAction() async throws {
        let harness = await Self.harness()
        let pairs = harness.keyList.state.pairs

        await harness.configuration.refresh()
        _ = harness.configuration.presentations(for: pairs)
        _ = harness.configuration.keyIndex(for: pairs)
        _ = harness.configuration.placement(for: "anything")

        let bastion = try Self.entry("bastion", in: harness)
        _ = harness.configuration.deletionTitle(for: bastion)
        _ = harness.configuration.deletionMessage(for: bastion)

        harness.form.beginEdit(bastion)
        harness.form.draft.user = "typed"
        _ = harness.form.keyChoices
        _ = harness.form.canSubmit
        harness.form.discard()

        harness.form.beginCreate()
        harness.form.draft.patterns = "typed"
        _ = harness.form.placementWarning
        harness.form.discard()

        #expect(harness.writer.calls.isEmpty)
        #expect(harness.keyWriter.touchedPaths.isEmpty)
    }

    // MARK: - 11.5 key management never edits configuration

    @Test("Renaming or deleting a key never modifies a configuration file")
    func keyOperationsLeaveTheConfigurationAlone() async throws {
        let harness = await Self.harness()
        let pair = try #require(harness.keyList.state.pairs.first)

        #expect(harness.keyList.deletionMessage(for: pair).contains("bastion"))

        harness.keyList.beginRename(of: pair)
        harness.keyList.renameProposal = "renamed"
        await harness.keyList.confirmRename()
        let renamed = try #require(harness.keyList.state.pairs.first)
        await harness.keyList.delete(renamed)

        #expect(!harness.keyWriter.touchedPaths.isEmpty)
        #expect(harness.writer.calls.isEmpty)
    }

    // MARK: - End to end, on a real file system

    @Test("An edit through the real adapters changes one block, keeps the mode and backs up once")
    func realEditInAScratchDirectory() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let original = "# mine\nHost a\n    User old   # note\n\nHost b\n    Port 22\n"
            let config = try scratch.file(named: "config", contents: Data(original.utf8))
            let bystander = try scratch.file(named: "known_hosts", contents: Data("untouched\n".utf8))
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path(percentEncoded: false))

            let reader = FileSystemSSHDirectoryReader()
            let status = SSHDirectoryStatusModel(
                resolver: SSHDirectoryResolver(reader: reader),
                launchEnvironment: Self.override(scratch.url),
                homeDirectory: Self.home,
                reader: reader
            )
            let model = SSHConfigModel(
                status: status,
                reader: reader,
                writer: FileSystemSSHConfigWriter(),
                homeDirectory: Self.home,
                userName: "alice"
            )
            await model.refresh()

            let entry = try #require(model.entries.first)
            let baseline = try #require(model.baseline(for: entry))
            let draft = ValidatedHostDraft(patterns: ["a"], hostName: nil, user: "new", port: nil, keyChoice: .unchanged)
            #expect(await model.update(entry, with: draft, baseline: baseline) == .completed)

            let written = String(decoding: try Data(contentsOf: config), as: UTF8.self)
            #expect(written == "# mine\nHost a\n    User new   # note\n\nHost b\n    Port 22\n")

            let attributes = try FileManager.default.attributesOfItem(atPath: config.path(percentEncoded: false))
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

            let backup = scratch.url.appending(path: ".config" + ConfigBackupLocation.suffix)
            #expect(String(decoding: try Data(contentsOf: backup), as: UTF8.self) == original)
            #expect(String(decoding: try Data(contentsOf: bystander), as: UTF8.self) == "untouched\n")

            let leftovers = try FileManager.default.contentsOfDirectory(atPath: scratch.url.path(percentEncoded: false))
                .filter { $0.contains(FileSystemSSHConfigWriter.temporaryMarker) }
            #expect(leftovers.isEmpty)
        }
    }

    // MARK: - 13.1 / 9.14 source scans

    @Test("No application source outside the file-access layer calls a file-system API")
    func fileSystemCallsAreConfinedToTheirLayer() throws {
        // Spelled in pieces so this test's own source does not match itself.
        let calls = [
            "Data(contents" + "Of", ".write(" + "to:", "renamex" + "_np", "un" + "link(",
            "fo" + "pen(", "real" + "path(", "O_" + "CREAT", "File" + "Manager",
        ]

        for source in try ProjectSources.application() where !source.isIn("open-ssh-gui/FileAccess") {
            for call in calls where source.text.contains(call) {
                #expect(
                    call == "File" + "Manager" && source.relativePath == "open-ssh-gui/OpenSSHGUIApp.swift",
                    "\(source.relativePath) calls \(call): \(source.lines(containing: call))"
                )
            }
        }
    }
}
