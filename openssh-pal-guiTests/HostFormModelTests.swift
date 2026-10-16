import Foundation
import Testing

/// The host form's state: what it is populated with, what it offers, what it refuses, and
/// where it goes when it is done. Driven through the real configuration and key list models
/// over in-memory doubles.
@MainActor
@Suite("Host form model")
struct HostFormModelTests {

    nonisolated private static let home = URL(filePath: "/fabricated/home", directoryHint: .isDirectory)
    nonisolated private static let keys = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)
    nonisolated private static let config = keys.appending(path: "config")
    nonisolated private static let ed25519Line = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHG/eTv0q9SPBgITfzHoiFX9BXBTCO4InzbH19BagKve user@host\n"

    nonisolated private static func file(_ name: String) -> URL { keys.appending(path: name) }

    private struct Harness {
        let form: HostFormModel
        let configuration: SSHConfigModel
        let writer: InMemorySSHConfigWriter
    }

    /// A loaded form over `files`, in a directory that also holds the named key pairs. An
    /// orphan is a public key whose private half is missing.
    private static func harness(
        _ files: [String: String],
        pairs: [String] = ["id_home", "id_work"],
        orphans: [String] = []
    ) async -> Harness {
        let keyFiles = pairs.flatMap { [$0, $0 + ".pub"] } + orphans.map { $0 + ".pub" }
        var data = Dictionary(uniqueKeysWithValues: files.map { (file($0.key), Data($0.value.utf8)) })
        let configData = data
        for name in pairs + orphans { data[file(name + ".pub")] = Data(ed25519Line.utf8) }

        let writer = InMemorySSHConfigWriter(files: configData)
        let reader = WriterBackedSSHDirectoryReader(
            base: InMemorySSHDirectoryReader(directories: [keys: (Array(files.keys) + keyFiles).map(file)], files: data),
            writer: writer
        )
        let status = SSHDirectoryStatusModel(
            resolver: SSHDirectoryResolver(reader: reader),
            launchEnvironment: LaunchEnvironment(
                arguments: [LaunchEnvironment.overrideArgument, keys.path(percentEncoded: false)],
                environmentVariables: [:]
            ),
            homeDirectory: home,
            reader: reader
        )
        let configuration = SSHConfigModel(status: status, reader: reader, writer: writer, homeDirectory: home, userName: "alice")
        let keyList = SSHKeyListModel(
            status: status,
            reader: reader,
            writer: InMemorySSHKeyWriter(),
            clipboard: RecordingClipboardWriter(),
            hostReferences: configuration
        )

        await configuration.refresh()
        await keyList.refresh()

        return Harness(form: HostFormModel(configuration: configuration, keys: keyList), configuration: configuration, writer: writer)
    }

    private static func name(_ raw: String) -> SSHKeyName { SSHKeyName.discovered(raw)! }

    private static func entry(_ name: String, in harness: Harness) throws -> HostEntry {
        try #require(harness.configuration.entries.first { $0.displayName == name })
    }

    private static func text(_ harness: Harness) -> String? {
        harness.writer.contents(of: config).map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: - 7.1 mode, draft and baseline

    @Test("No form is open until one is begun")
    func startsOnTheList() async {
        let harness = await Self.harness(["config": "Host a\n"])
        #expect(harness.form.mode == nil)
    }

    @Test("An edit is populated from the entry, and captures its file's bytes as the baseline")
    func editIsPopulated() async throws {
        let text = "Host web\n    HostName 10.0.0.5\n    User deploy\n    Port 2222\n    IdentityFile /fabricated/keys/id_work\n"
        let harness = await Self.harness(["config": text])
        let entry = try Self.entry("web", in: harness)

        harness.form.beginEdit(entry)

        #expect(harness.form.mode == .edit(entry))
        #expect(harness.form.draft == HostDraft(patterns: "web", hostName: "10.0.0.5", user: "deploy", port: "2222", keyChoice: .pair(Self.name("id_work"))))
        #expect(harness.form.baseline == Data(text.utf8))
    }

    @Test("A create starts empty, with no key, against config's current bytes")
    func createStartsEmpty() async {
        let harness = await Self.harness(["config": "Host a\n"])
        harness.form.beginCreate()

        #expect(harness.form.mode == .create)
        #expect(harness.form.draft == .empty)
        #expect(harness.form.baseline == Data("Host a\n".utf8))

        let empty = await Self.harness([:])
        empty.form.beginCreate()
        #expect(empty.form.baseline == nil)
    }

    @Test("Discarding returns to the list and writes nothing")
    func discardWritesNothing() async throws {
        let harness = await Self.harness(["config": "Host a\n"])
        harness.form.beginEdit(try Self.entry("a", in: harness))
        harness.form.draft.user = "changed"

        harness.form.discard()

        #expect(harness.form.mode == nil)
        #expect(harness.form.draft == .empty)
        #expect(harness.writer.calls.isEmpty)
    }

    @Test("A repeated HostName, User or Port is presented read-only, with the reason")
    func repeatedValuesAreReadOnly() async throws {
        let harness = await Self.harness(["config": "Host a\n    HostName one\n    HostName two\n    User u\n"])
        harness.form.beginEdit(try Self.entry("a", in: harness))

        #expect(harness.form.readOnlyReason(for: .hostName) != nil)
        #expect(harness.form.readOnlyReason(for: .user) == nil)
        #expect(harness.form.readOnlyReason(for: .patterns) == nil)
    }

    @Test("A pattern containing a space is presented read-only, because the field cannot hold it")
    func quotedPatternIsReadOnly() async throws {
        let harness = await Self.harness(["config": "Host \"my host\"\n"])
        harness.form.beginEdit(try Self.entry("my host", in: harness))
        #expect(harness.form.readOnlyReason(for: .patterns) != nil)
    }

    @Test("Several IdentityFile values, or one that does not resolve, are kept unless replaced")
    func unrepresentableKeysAreKept() async throws {
        let harness = await Self.harness([
            "config": "Host many\n    IdentityFile /fabricated/keys/id_work\n    IdentityFile /fabricated/keys/id_home\nHost odd\n    IdentityFile ~/keys/%h\n",
        ])

        for name in ["many", "odd"] {
            harness.form.beginEdit(try Self.entry(name, in: harness))
            #expect(harness.form.draft.keyChoice == .unchanged)
            #expect(harness.form.keyChoices.first?.choice == .unchanged)
            #expect(harness.form.keyChoices.first?.detail?.contains("/fabricated/keys") == true || name == "odd")
        }
    }

    @Test("A completed edit returns to the list and the entry shows its new value")
    func completedEditReturnsToTheList() async throws {
        let harness = await Self.harness(["config": "Host a\n    User old\n"])
        harness.form.beginEdit(try Self.entry("a", in: harness))
        harness.form.draft.user = "new"

        await harness.form.submit()

        #expect(harness.form.mode == nil)
        #expect(try Self.entry("a", in: harness).user?.value == "new")
    }

    @Test("A file changed meanwhile closes the form; a failed write keeps it open")
    func outcomesDecideWhetherTheFormStays() async throws {
        let changed = await Self.harness(["config": "Host a\n"])
        changed.form.beginEdit(try Self.entry("a", in: changed))
        changed.form.draft.user = "u"
        changed.writer.simulateExternalChange(of: Self.config, to: Data("Host a\nHost b\n".utf8))
        await changed.form.submit()
        #expect(changed.form.mode == nil)

        let failing = await Self.harness(["config": "Host a\n"])
        failing.form.beginEdit(try Self.entry("a", in: failing))
        failing.form.draft.user = "u"
        failing.writer.setFailure(.accessDenied(Self.config), for: Self.config)
        await failing.form.submit()
        #expect(failing.form.mode != nil)
        #expect(failing.form.draft.user == "u")
    }

    @Test("Saving with the key left as it was does not rewrite how the IdentityFile is spelled")
    func unchangedKeyKeepsItsSpelling() async throws {
        let harness = await Self.harness(["config": "Host a\n    IdentityFile /fabricated/keys/./id_work\n"])
        harness.form.beginEdit(try Self.entry("a", in: harness))
        #expect(harness.form.draft.keyChoice == .pair(Self.name("id_work")))
        harness.form.draft.user = "u"

        await harness.form.submit()

        #expect(Self.text(harness) == "Host a\n    IdentityFile /fabricated/keys/./id_work\n    User u\n")
    }

    // MARK: - 7.2 key choices

    @Test("No key plus every pair is offered, and a pair without a private key cannot be chosen")
    func keyChoices() async throws {
        let harness = await Self.harness(["config": "Host a\n"], orphans: ["orphan"])
        harness.form.beginCreate()

        #expect(harness.form.keyChoices.map(\.choice) == [.none, .pair(Self.name("id_home")), .pair(Self.name("id_work")), .pair(Self.name("orphan"))])
        let orphan = try #require(harness.form.keyChoices.last)
        #expect(!orphan.isAvailable)

        harness.form.select(.pair(Self.name("orphan")))
        #expect(harness.form.draft.keyChoice == .none)

        harness.form.select(.pair(Self.name("id_work")))
        #expect(harness.form.draft.keyChoice == .pair(Self.name("id_work")))
        #expect(harness.form.noKeysMessage == nil)
    }

    @Test("With no key pairs only no key is offered, and the form says why")
    func noPairs() async {
        let harness = await Self.harness(["config": "Host a\n"], pairs: [])
        harness.form.beginCreate()

        #expect(harness.form.keyChoices.map(\.choice) == [.none])
        #expect(harness.form.noKeysMessage != nil)
    }

    @Test("A pair used by another concrete host names it, leaving out the host being edited")
    func sharedPairsNameTheirHosts() async throws {
        let harness = await Self.harness(["config": "Host a\n    IdentityFile /fabricated/keys/id_work\nHost b\n"])
        let work = HostKeyChoice.pair(Self.name("id_work"))

        harness.form.beginCreate()
        #expect(harness.form.keyChoices.first { $0.choice == work }?.sharingHosts == ["a"])

        harness.form.beginEdit(try Self.entry("a", in: harness))
        #expect(harness.form.keyChoices.first { $0.choice == work }?.sharingHosts == [])

        harness.form.beginEdit(try Self.entry("b", in: harness))
        harness.form.select(work)
        #expect(harness.form.selectedKeyStatus?.contains("a") == true)
        // 3.7 / 4.4: advisory only — the shared key does not stand in the way.
        #expect(harness.form.canSubmit)
    }

    @Test("Submitting is available exactly when every value is accepted")
    func submitAvailability() async {
        let harness = await Self.harness(["config": "Host a\n"])
        harness.form.beginCreate()

        #expect(!harness.form.canSubmit)
        #expect(!harness.form.fieldValidation(for: .patterns).isValid)

        harness.form.draft.patterns = "web"
        #expect(harness.form.canSubmit)
        #expect(harness.form.fieldValidation(for: .patterns).isValid)

        for (field, value) in [(HostDraftField.port, "0"), (.hostName, "a b"), (.user, "#"), (.patterns, "a")] {
            var draft = HostDraft(patterns: "web", hostName: "", user: "", port: "", keyChoice: .none)
            switch field {
            case .patterns: draft.patterns = value
            case .hostName: draft.hostName = value
            case .user: draft.user = value
            case .port: draft.port = value
            }
            harness.form.draft = draft
            #expect(!harness.form.canSubmit, "\(field)")
            #expect(!harness.form.fieldValidation(for: field).isValid, "\(field)")
        }
    }

    @Test("A create that an earlier block would pre-empt carries a warning naming it and its file")
    func placementWarning() async {
        let harness = await Self.harness(["config": "Include work\n\nHost *\n", "work": "Host *.corp\n    User corp\n"])
        harness.form.beginCreate()

        harness.form.draft.patterns = "db.corp"
        let warning = harness.form.placementWarning
        #expect(warning?.message.contains("*.corp") == true)
        #expect(warning?.message.contains("work") == true)

        harness.form.draft.patterns = "web"
        #expect(harness.form.placementWarning == nil)
    }

    @Test("A completed create returns to the list and presents the new entry")
    func completedCreate() async throws {
        let harness = await Self.harness(["config": "Host a\n"])
        harness.form.beginCreate()
        harness.form.draft.patterns = "new"
        harness.form.select(.pair(Self.name("id_work")))

        await harness.form.submit()

        #expect(harness.form.mode == nil)
        #expect(Self.text(harness) == "Host a\n\nHost new\n    IdentityFile /fabricated/keys/id_work\n")
        #expect(harness.configuration.entries.map(\.displayName) == ["a", "new"])
    }
}
