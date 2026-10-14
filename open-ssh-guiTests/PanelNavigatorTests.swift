import Foundation
import Testing

/// What switching tabs does to the forms behind them. The panel's view only stores which tab is
/// selected; every rule about leaving and entering a tab lives here, where it can be tested.
@MainActor
@Suite("Panel navigation")
struct PanelNavigatorTests {

    nonisolated private static let home = URL(filePath: "/fabricated/home", directoryHint: .isDirectory)
    nonisolated private static let keys = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)

    nonisolated private static func pair(_ name: String) -> SSHKeyPair {
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

    private struct Harness {
        let navigator: PanelNavigator
        let keyList: SSHKeyListModel
        let newKey: NewKeyFormModel
        let hostForm: HostFormModel
        let generator: StubSSHKeyGenerator
    }

    private static func harness() async -> Harness {
        let reader = InMemorySSHDirectoryReader(
            directories: [keys: [keys.appending(path: "config")]],
            files: [keys.appending(path: "config"): Data("Host a\n".utf8)]
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
        let configuration = SSHConfigModel(
            status: status,
            reader: reader,
            writer: InMemorySSHConfigWriter(),
            homeDirectory: home,
            userName: "alice"
        )
        let keyList = SSHKeyListModel(
            status: status,
            reader: reader,
            writer: InMemorySSHKeyWriter(),
            clipboard: RecordingClipboardWriter(),
            hostReferences: configuration
        )
        let generator = StubSSHKeyGenerator(outcome: .success(pair("work_key")))
        let newKey = NewKeyFormModel(generator: generator, defaultComment: "user@host")
        let hostForm = HostFormModel(configuration: configuration, keys: keyList)

        await configuration.refresh()
        await keyList.refresh()

        return Harness(
            navigator: PanelNavigator(keys: keyList, newKey: newKey, hostForm: hostForm),
            keyList: keyList,
            newKey: newKey,
            hostForm: hostForm,
            generator: generator
        )
    }

    @Test("The panel opens on the Keys tab, and the tabs are Keys, Hosts and New Key in that order")
    func initialTab() {
        #expect(PanelTab.initial == .keys)
        #expect(PanelTab.allCases.map(\.title) == ["Keys", "Hosts", "New Key"])
    }

    @Test("Entering New Key opens the create form against the resolved directory")
    func enteringNewKeyOpensTheForm() async {
        let harness = await Self.harness()
        harness.navigator.select(.newKey, leaving: .keys)

        #expect(harness.newKey.name == "id_ed25519")
        #expect(harness.newKey.canGenerate)
    }

    @Test("Leaving New Key drops what was typed, the passphrase included, without completing")
    func leavingNewKeyDiscards() async {
        let harness = await Self.harness()
        harness.navigator.select(.newKey, leaving: .keys)
        harness.newKey.passphraseText = "hunter2"
        harness.newKey.confirmationText = "hunter2"

        harness.navigator.select(.hosts, leaving: .newKey)

        #expect(harness.newKey.passphrase == .none)
        #expect(harness.newKey.confirmation == .none)
        #expect(harness.newKey.completion == nil)
    }

    @Test("Leaving New Key mid-generation lets it finish, and the outcome selects Keys")
    func leavingMidGeneration() async {
        let harness = await Self.harness()
        harness.generator.hold()
        harness.navigator.select(.newKey, leaving: .keys)
        harness.newKey.name = "work_key"
        harness.newKey.submit()
        await Task.yield()

        harness.navigator.select(.hosts, leaving: .newKey)
        #expect(harness.newKey.isGenerating)

        // Coming back while it runs shows it running, rather than a fresh form.
        harness.navigator.select(.newKey, leaving: .hosts)
        #expect(harness.newKey.isGenerating)
        harness.navigator.select(.hosts, leaving: .newKey)

        harness.generator.release()
        await harness.newKey.waitForGeneration()

        #expect(await harness.navigator.adoptCompletion() == .keys)
        #expect(harness.keyList.notice == .generated(SSHKeyName.discovered("work_key")!))
        #expect(harness.newKey.completion == nil)
    }

    @Test("With nothing finished, there is nothing to adopt and the tab stays")
    func nothingToAdopt() async {
        let harness = await Self.harness()
        #expect(await harness.navigator.adoptCompletion() == nil)
    }

    @Test("Leaving Hosts discards an open host form without writing")
    func leavingHostsDiscards() async {
        let harness = await Self.harness()
        harness.hostForm.beginCreate()
        harness.hostForm.draft.patterns = "typed"

        harness.navigator.select(.keys, leaving: .hosts)

        #expect(harness.hostForm.mode == nil)
        #expect(harness.hostForm.draft == .empty)
    }

    @Test("Selecting the tab already shown changes nothing")
    func reselectingIsANoOp() async {
        let harness = await Self.harness()
        harness.hostForm.beginCreate()
        harness.navigator.select(.hosts, leaving: .hosts)
        #expect(harness.hostForm.mode == .create)
    }
}
