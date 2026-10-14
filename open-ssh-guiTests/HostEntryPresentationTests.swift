import Foundation
import Testing

/// Every string the host list renders, computed without a view. A view that composes its own
/// text is a view that cannot be checked without rendering it.
@Suite("Host entry presentation")
nonisolated struct HostEntryPresentationTests {

    private static let config = URL(filePath: "/fabricated/keys/config")

    private static func entry(_ text: String) -> HostEntry {
        SSHConfigParser().parse(Data(text.utf8), at: config, inclusionChain: [], writability: .writable).entries[0]
    }

    private static func presentation(
        _ text: String,
        associations: [KeyAssociation] = [],
        sharing: [String] = [],
        file: String = "config",
        inConfig: Bool = true
    ) -> HostEntryPresentation {
        HostEntryPresentation(
            entry: entry(text),
            associations: associations,
            sharingHosts: sharing,
            file: file,
            isDeclaredInConfig: inConfig
        )
    }

    // MARK: - 2.2 title and summary

    @Test("The title is the patterns, and the summary reads user@host:port")
    func titleAndSummary() {
        let full = Self.presentation("Host web prod\n    HostName 10.0.0.5\n    User deploy\n    Port 2222\n")
        #expect(full.title == "web prod")
        #expect(full.summary == "deploy@10.0.0.5:2222")

        #expect(Self.presentation("Host web\n    HostName h\n").summary == "h")
        #expect(Self.presentation("Host web\n    User u\n    Port 22\n").summary == "User u, Port 22")
        #expect(Self.presentation("Host web\n").summary == "No HostName, User or Port declared")
    }

    // MARK: - 2.4–2.7 key text

    @Test("Each association has its own words, and no IdentityFile means default identities")
    func keyText() throws {
        let name = try #require(SSHKeyName.discovered("id_work"))

        #expect(Self.presentation("Host a\n").keySummary == "Default identities")
        #expect(Self.presentation("Host a\n", associations: [.listed(name)]).keySummary == "id_work")

        let unlisted = Self.presentation("Host a\n", associations: [.unlisted(raw: "~/keys/old")]).keySummary
        #expect(unlisted.contains("~/keys/old"))
        #expect(unlisted.contains("not a listed key"))

        let unresolved = Self.presentation("Host a\n", associations: [.unresolved(raw: "~/keys/%h", .connectionToken("%h"))]).keySummary
        #expect(unresolved.contains("~/keys/%h"))
        #expect(unresolved.contains("unresolved"))

        #expect(Self.presentation("Host a\n", associations: [.disabled]).keySummary.contains("none"))
        #expect(Self.presentation("Host a\n", associations: [.listed(name), .disabled]).keyTexts.count == 2)
    }

    // MARK: - 2.9 / 2.10 attribution and pattern entries

    @Test("The declaring file is named only when it is not config")
    func attribution() {
        #expect(Self.presentation("Host a\n").fileText == nil)
        #expect(Self.presentation("Host a\n", file: "config.d/work", inConfig: false).fileText == "Declared in config.d/work")
    }

    @Test("A pattern entry is marked, and a concrete host is not")
    func patternMarker() {
        #expect(Self.presentation("Host *.corp\n").patternMarker != nil)
        #expect(Self.presentation("Host web\n").patternMarker == nil)
    }

    // MARK: - 3.1 / 3.4–3.6 the shared-key warning

    @Test("A shared key shows the warning symbol and colour together, naming the other hosts")
    func sharedKeyWarning() {
        let shared = Self.presentation("Host a\n", sharing: ["b", "c"])
        #expect(shared.isShared)
        #expect(shared.symbolName == StatusRole.warning.symbolName)
        #expect(shared.symbolColor == .warning)
        #expect(shared.sharingWarning == "Key shared with b, c")

        let alone = Self.presentation("Host a\n")
        #expect(!alone.isShared)
        #expect(alone.sharingWarning == nil)
        #expect(alone.symbolName != StatusRole.warning.symbolName)
    }

    @Test("The accessibility label says everything the row shows, including who shares the key")
    func accessibilityLabel() throws {
        let name = try #require(SSHKeyName.discovered("id_work"))
        let label = Self.presentation(
            "Host *.corp\n    User u\n",
            associations: [.listed(name)],
            sharing: ["bastion"],
            file: "config.d/work",
            inConfig: false
        ).accessibilityLabel

        for fragment in ["*.corp", "Pattern", "User u", "id_work", "config.d/work", "shared", "bastion"] {
            #expect(label.contains(fragment), "\(fragment)")
        }
    }

    @Test("A read-only entry carries its reason")
    func readOnly() {
        let entry = Self.entry("Host a\n").withWritability(.readOnly(.outsideDirectory))
        let presentation = HostEntryPresentation(entry: entry, associations: [], sharingHosts: [], file: "/etc/x", isDeclaredInConfig: false)
        #expect(presentation.readOnlyReason == ConfigReadOnlyReason.outsideDirectory.reason)
        #expect(Self.presentation("Host a\n").readOnlyReason == nil)
    }
}
