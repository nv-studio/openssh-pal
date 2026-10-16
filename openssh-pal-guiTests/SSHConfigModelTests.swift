import Foundation
import Testing

/// The configuration model over in-memory doubles: what it loads, what it writes, and above all
/// what it refuses to write. Nothing here touches the file system.
@MainActor
@Suite("Configuration model")
struct SSHConfigModelTests {

    nonisolated private static let home = URL(filePath: "/fabricated/home", directoryHint: .isDirectory)
    nonisolated private static let keys = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)
    nonisolated private static let config = keys.appending(path: "config")

    nonisolated private static func file(_ name: String) -> URL { keys.appending(path: name) }

    private struct Harness {
        let model: SSHConfigModel
        let writer: InMemorySSHConfigWriter
    }

    /// A model over `files` (relative to the override directory) plus `absoluteFiles`.
    private static func harness(
        _ files: [String: String] = [:],
        absoluteFiles: [URL: String] = [:],
        directories: [URL: [URL]] = [:],
        links: [URL: URL] = [:],
        failures: [URL: FileAccessError] = [:],
        launch: LaunchEnvironment? = nil
    ) -> Harness {
        var data = Dictionary(uniqueKeysWithValues: files.map { (file($0.key), Data($0.value.utf8)) })
        for (url, text) in absoluteFiles { data[url] = Data(text.utf8) }

        let writer = InMemorySSHConfigWriter(files: data, links: links)
        let isDefault = launch != nil
        let base = InMemorySSHDirectoryReader(
            directories: isDefault ? directories : directories.merging([keys: files.keys.map(file)]) { existing, _ in existing },
            files: data,
            failures: failures
        )
        let reader = WriterBackedSSHDirectoryReader(base: base, writer: writer)

        let status = SSHDirectoryStatusModel(
            resolver: SSHDirectoryResolver(reader: reader),
            launchEnvironment: launch ?? LaunchEnvironment(
                arguments: [LaunchEnvironment.overrideArgument, keys.path(percentEncoded: false)],
                environmentVariables: [:]
            ),
            homeDirectory: home,
            reader: reader
        )

        return Harness(
            model: SSHConfigModel(status: status, reader: reader, writer: writer, homeDirectory: home, userName: "alice"),
            writer: writer
        )
    }

    private static func pair(_ name: String) -> SSHKeyPair {
        let key = SSHKeyName.discovered(name)!
        return SSHKeyPair(
            location: SSHKeyPairLocation(
                name: key,
                publicKeyURL: key.publicKeyURL(in: keys),
                privateKeyURL: key.privateKeyURL(in: keys),
                certificateURL: nil
            ),
            publicKey: .failure(.fileUnreadable)
        )
    }

    private static func draft(
        _ patterns: [String],
        hostName: String? = nil,
        user: String? = nil,
        key: HostKeyChoice = .unchanged
    ) -> ValidatedHostDraft {
        ValidatedHostDraft(patterns: patterns, hostName: hostName, user: user, port: nil, keyChoice: key)
    }

    private static func text(_ writer: InMemorySSHConfigWriter, _ url: URL) -> String? {
        writer.contents(of: url).map { String(decoding: $0, as: UTF8.self) }
    }

    private static func entry(_ name: String, in model: SSHConfigModel) throws -> HostEntry {
        try #require(model.entries.first { $0.displayName == name })
    }

    // MARK: - 6.1 states

    @Test("Before the first refresh the model is loading, not empty")
    func startsLoading() {
        #expect(Self.harness().model.state == .loading)
    }

    @Test("A readable config is loaded with its entries")
    func loaded() async throws {
        let model = Self.harness(["config": "Host a\nHost b\n"]).model
        await model.refresh()

        #expect(model.entries.map(\.displayName) == ["a", "b"])
        #expect(model.state.failureReason == nil)
        #expect(model.notice == nil)
    }

    @Test("No config file is its own state, distinct from an unreadable one")
    func noConfigFile() async {
        let model = Self.harness([:]).model
        await model.refresh()
        #expect(model.state == .noConfigFile)
        #expect(model.entries.isEmpty)
    }

    @Test("A config that cannot be read reports why")
    func unreadable() async {
        let model = Self.harness(["config": "Host a\n"], failures: [Self.config: .accessDenied(Self.config)]).model
        await model.refresh()
        #expect(model.state == .unreadable(.accessDenied(Self.config)))
        #expect(model.state.failureReason != nil)
    }

    @Test("A rejected override is no directory at all")
    func noDirectory() async {
        let missing = Self.harness(
            [:],
            launch: LaunchEnvironment(arguments: [LaunchEnvironment.overrideArgument, "/fabricated/missing"], environmentVariables: [:])
        ).model
        await missing.refresh()
        #expect(missing.state == .noDirectory(.overridePathDoesNotExist(URL(filePath: "/fabricated/missing"))))
    }

    @Test("A partial load keeps every readable entry and reports what went wrong")
    func partialLoad() async throws {
        let locked = Self.file("locked")
        let model = Self.harness(
            ["config": "Include locked\nHost a\n", "locked": "Host x\n"],
            failures: [locked: .accessDenied(locked)]
        ).model
        await model.refresh()

        #expect(model.entries.map(\.displayName) == ["a"])
        #expect(model.state.configuration?.issues == [.unreadable(file: locked, .accessDenied(locked))])
    }

    @Test("An entry in a file linked outside the directory is read-only")
    func outwardLinkIsReadOnly() async throws {
        let link = Self.file("work")
        let target = URL(filePath: "/fabricated/elsewhere/work")
        let model = Self.harness(
            ["config": "Include work\nHost a\n"],
            absoluteFiles: [target: "Host linked\n"],
            links: [link: target]
        ).model
        await model.refresh()

        #expect(try Self.entry("linked", in: model).writability == .readOnly(.symbolicLinkOutsideDirectory))
        #expect(try Self.entry("a", in: model).writability == .writable)
    }

    @Test("The key index is computed for whatever pairs are supplied")
    func keyIndex() async throws {
        let model = Self.harness(["config": "Host a\n    IdentityFile /fabricated/keys/id_work\n"]).model
        await model.refresh()

        let index = model.keyIndex(for: [Self.pair("id_work")])
        #expect(index.associations(for: try Self.entry("a", in: model).id) == [.listed(SSHKeyName.discovered("id_work")!)])
        #expect(model.keyIndex(for: []).associations(for: try Self.entry("a", in: model).id) == [.unlisted(raw: "/fabricated/keys/id_work")])
    }

    @Test("Presentations attribute included entries to their file and flag shared keys")
    func presentations() async throws {
        let model = Self.harness([
            "config": "Include work\nHost a\n    IdentityFile /fabricated/keys/id_work\n",
            "work": "Host w\n    IdentityFile /fabricated/keys/id_work\n",
        ]).model
        await model.refresh()

        let presentations = model.presentations(for: [Self.pair("id_work")])
        #expect(presentations.map(\.title) == ["w", "a"])
        #expect(presentations.map(\.fileText) == ["Declared in work", nil])
        #expect(presentations.map(\.sharingHosts) == [["a"], ["w"]])
        #expect(model.canCreate)
    }

    @Test("The issue summary names the first issue and counts the rest")
    func issueSummary() async throws {
        let model = Self.harness(["config": "Include %h\nInclude %r\nHost a\n"]).model
        await model.refresh()
        #expect(model.issueSummary?.contains("and 1 more") == true)
    }

    // MARK: - 6.2 edit

    @Test("An edit writes only the included file that declares the block, after backing it up")
    func editWritesOnlyTheDeclaringFile() async throws {
        let harness = Self.harness(["config": "Include work\nHost a\n", "work": "Host w\n    User old\n"])
        await harness.model.refresh()
        let entry = try Self.entry("w", in: harness.model)
        let baseline = try #require(harness.model.baseline(for: entry))

        let outcome = await harness.model.update(entry, with: Self.draft(["w"], user: "new"), baseline: baseline)

        #expect(outcome == .completed)
        #expect(Self.text(harness.writer, Self.file("work")) == "Host w\n    User new\n")
        #expect(Self.text(harness.writer, Self.config) == "Include work\nHost a\n")
        #expect(harness.writer.calls == [
            .backUp(Self.file("work"), to: Self.file(".work.open-ssh-gui-backup")),
            .replace(Self.file("work")),
        ])
        #expect(harness.model.notice == .updated("w"))
        // 1.12 / 5.10: the list is re-read and shows the new value.
        #expect(try Self.entry("w", in: harness.model).user?.value == "new")
    }

    @Test("A file changed since the form opened is not written; the list is re-read")
    func externalChangeIsNotOverwritten() async throws {
        let harness = Self.harness(["config": "Host a\n    User old\n"])
        await harness.model.refresh()
        let entry = try Self.entry("a", in: harness.model)
        let baseline = try #require(harness.model.baseline(for: entry))

        harness.writer.simulateExternalChange(of: Self.config, to: Data("Host a\n    User edited\n".utf8))
        let outcome = await harness.model.update(entry, with: Self.draft(["a"], user: "mine"), baseline: baseline)

        #expect(outcome == .changedOnDisk)
        #expect(Self.text(harness.writer, Self.config) == "Host a\n    User edited\n")
        #expect(harness.model.notice == .changedOnDisk(fileName: "config"))
        #expect(try Self.entry("a", in: harness.model).user?.value == "edited")
    }

    @Test("The backup is taken before the first change and never replaced afterwards")
    func backupIsTakenOnce() async throws {
        let harness = Self.harness(["config": "Host a\n    User one\n"])
        await harness.model.refresh()

        for user in ["two", "three"] {
            let entry = try Self.entry("a", in: harness.model)
            let baseline = try #require(harness.model.baseline(for: entry))
            #expect(await harness.model.update(entry, with: Self.draft(["a"], user: user), baseline: baseline) == .completed)
        }

        #expect(Self.text(harness.writer, Self.file(".config.open-ssh-gui-backup")) == "Host a\n    User one\n")
        #expect(Self.text(harness.writer, Self.config) == "Host a\n    User three\n")
    }

    @Test("A second change is refused while one is running")
    func secondMutationIsRefused() async throws {
        let harness = Self.harness(["config": "Host a\nHost b\n"])
        await harness.model.refresh()
        let a = try Self.entry("a", in: harness.model)
        let b = try Self.entry("b", in: harness.model)
        let baseline = try #require(harness.model.baseline(for: a))

        harness.writer.hold()
        let first = Task { await harness.model.update(a, with: Self.draft(["a"], user: "u"), baseline: baseline) }
        while !harness.model.operation.isInFlight { await Task.yield() }

        let callsBefore = harness.writer.calls.count
        #expect(await harness.model.delete(b) == .refused)
        #expect(await harness.model.create(Self.draft(["c"]), baseline: baseline) == .refused)
        #expect(harness.writer.calls.count == callsBefore)

        harness.writer.release()
        #expect(await first.value == .completed)
        #expect(harness.model.operation == .idle)
    }

    @Test("A refresh while a change is running does not race it")
    func refreshWaitsForTheChange() async throws {
        let harness = Self.harness(["config": "Host a\n"])
        await harness.model.refresh()
        let a = try Self.entry("a", in: harness.model)
        let baseline = try #require(harness.model.baseline(for: a))

        harness.writer.hold()
        let change = Task { await harness.model.update(a, with: Self.draft(["a"], user: "u"), baseline: baseline) }
        while !harness.model.operation.isInFlight { await Task.yield() }

        await harness.model.refresh()
        #expect(harness.model.operation.isInFlight)

        harness.writer.release()
        _ = await change.value
        #expect(try Self.entry("a", in: harness.model).user?.value == "u")
    }

    @Test("A failed write reports the reason naming the file and leaves it untouched")
    func failureIsReported() async throws {
        let harness = Self.harness(["config": "Host a\n"])
        await harness.model.refresh()
        let entry = try Self.entry("a", in: harness.model)
        let baseline = try #require(harness.model.baseline(for: entry))
        harness.writer.setFailure(.accessDenied(Self.config), for: Self.config)

        #expect(await harness.model.update(entry, with: Self.draft(["a"], user: "u"), baseline: baseline) == .failed)
        #expect(harness.model.notice == .failed(reason: SSHConfigWriteError.accessDenied(Self.config).reason))
        #expect(Self.text(harness.writer, Self.config) == "Host a\n")
    }

    @Test("A read-only entry is never written")
    func readOnlyIsRefused() async throws {
        let link = Self.file("work")
        let target = URL(filePath: "/fabricated/elsewhere/work")
        let harness = Self.harness(["config": "Include work\n"], absoluteFiles: [target: "Host linked\n"], links: [link: target])
        await harness.model.refresh()
        let entry = try Self.entry("linked", in: harness.model)

        #expect(await harness.model.update(entry, with: Self.draft(["linked"], user: "u"), baseline: Data("Host linked\n".utf8)) == .refused)
        #expect(await harness.model.delete(entry) == .refused)
        #expect(harness.writer.calls.isEmpty)
    }

    @Test("A backup an include would read refuses the write, naming the include")
    func backupMatchedByAnIncludeIsRefused() async throws {
        let harness = Self.harness(["config": "Include .*\nHost a\n"])
        await harness.model.refresh()
        let entry = try Self.entry("a", in: harness.model)
        let baseline = try #require(harness.model.baseline(for: entry))

        #expect(await harness.model.update(entry, with: Self.draft(["a"], user: "u"), baseline: baseline) == .failed)
        #expect(harness.writer.calls.isEmpty)
        #expect(harness.model.notice?.message.contains("Include") == true)
    }

    // MARK: - 8 delete

    @Test("Deleting removes the block from the declaring file and touches nothing else")
    func deleteTouchesOnlyTheConfig() async throws {
        let harness = Self.harness(["config": "Host a\n    IdentityFile /fabricated/keys/id_work\n\nHost b\n"])
        await harness.model.refresh()

        #expect(await harness.model.delete(try Self.entry("a", in: harness.model)) == .completed)

        #expect(Self.text(harness.writer, Self.config) == "Host b\n")
        // 8.4: the key the block named is not a path this writer was even pointed at.
        #expect(Set(harness.writer.touchedPaths) == [Self.config, Self.file(".config.open-ssh-gui-backup")])
        #expect(harness.model.notice == .deleted("a"))
        #expect(harness.model.entries.map(\.displayName) == ["b"])
    }

    @Test("The deletion confirmation names the entry and the file that declares it")
    func deletionConfirmation() async throws {
        let harness = Self.harness(["config": "Include work\n", "work": "Host w\n"])
        await harness.model.refresh()
        let entry = try Self.entry("w", in: harness.model)

        #expect(harness.model.deletionTitle(for: entry).contains("w"))
        #expect(harness.model.deletionMessage(for: entry).contains("work"))
        #expect(harness.model.deletionMessage(for: entry).contains("not deleted"))
    }

    // MARK: - 6.3 create

    @Test("A new host is inserted at the placement point and appears after the reload")
    func createInserts() async throws {
        let harness = Self.harness(["config": "Host a\n\nHost *\n    User all\n"])
        await harness.model.refresh()
        let baseline = harness.model.configBaseline

        let outcome = await harness.model.create(Self.draft(["new"], hostName: "n.example.com", key: .none), baseline: baseline)

        #expect(outcome == .completed)
        #expect(Self.text(harness.writer, Self.config) == "Host a\n\nHost new\n    HostName n.example.com\n\nHost *\n    User all\n")
        #expect(harness.model.entries.map(\.displayName) == ["a", "new", "*"])
        #expect(harness.model.notice == .created("new"))
    }

    @Test("With no config, one is created holding only the new block, without a backup")
    func createMakesTheFile() async throws {
        let harness = Self.harness([:])
        await harness.model.refresh()
        #expect(harness.model.configBaseline == nil)

        #expect(await harness.model.create(Self.draft(["new"], key: .none), baseline: nil) == .completed)

        #expect(harness.writer.calls == [.create(Self.config)])
        #expect(Self.text(harness.writer, Self.config) == "Host new\n")
        #expect(harness.model.entries.map(\.displayName) == ["new"])
    }

    @Test("An absent SSH directory is reported and nothing is created")
    func absentDirectory() async {
        let harness = Self.harness([:], launch: LaunchEnvironment(arguments: [], environmentVariables: [:]))
        await harness.model.refresh()

        #expect(await harness.model.create(Self.draft(["new"], key: .none), baseline: nil) == .refused)
        #expect(harness.writer.calls.isEmpty)
        #expect(harness.model.notice?.message.contains("does not exist") == true)
    }

    @Test("A config that changed since the form opened is not written by a create")
    func createAgainstAStaleBaseline() async throws {
        let harness = Self.harness(["config": "Host a\n"])
        await harness.model.refresh()
        let baseline = harness.model.configBaseline
        harness.writer.simulateExternalChange(of: Self.config, to: Data("Host a\nHost b\n".utf8))

        #expect(await harness.model.create(Self.draft(["new"], key: .none), baseline: baseline) == .changedOnDisk)
        #expect(Self.text(harness.writer, Self.config) == "Host a\nHost b\n")
    }

    // MARK: - 6.4 host references

    @Test("Host references name every host whose IdentityFile resolves to the pair")
    func references() async throws {
        let model = Self.harness([
            "config": "Host a\n    IdentityFile /fabricated/keys/id_work\nHost *\n    IdentityFile /fabricated/keys/id_work.pub\nHost b\n",
        ]).model
        await model.refresh()

        #expect(model.hostReferences(to: Self.pair("id_work")) == .references(hosts: ["a", "*"], hasUnresolved: false))
        #expect(model.hostReferences(to: Self.pair("id_home")) == .references(hosts: [], hasUnresolved: false))
    }

    @Test("Unresolved IdentityFile values are reported as possibly naming the key")
    func unresolvedReferences() async throws {
        let model = Self.harness(["config": "Host a\n    IdentityFile ~/keys/%h\n"]).model
        await model.refresh()
        #expect(model.hostReferences(to: Self.pair("id_work")) == .references(hosts: [], hasUnresolved: true))
    }

    @Test("A configuration that was not read cannot vouch for anything")
    func unavailableReferences() async {
        let unread = Self.harness(["config": "Host a\n"]).model
        guard case .unavailable = unread.hostReferences(to: Self.pair("id_work")) else {
            Issue.record("an unloaded configuration reported references")
            return
        }

        let locked = Self.harness(["config": "Host a\n"], failures: [Self.config: .accessDenied(Self.config)]).model
        await locked.refresh()
        guard case .unavailable = locked.hostReferences(to: Self.pair("id_work")) else {
            Issue.record("an unreadable configuration reported references")
            return
        }

        let empty = Self.harness([:]).model
        await empty.refresh()
        #expect(empty.hostReferences(to: Self.pair("id_work")) == .references(hosts: [], hasUnresolved: false))
    }
}
