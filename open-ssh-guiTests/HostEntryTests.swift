import Foundation
import Testing

/// The projections a host entry carries, and the value semantics every configuration type
/// relies on: an edit is computed from one load and compared against another, so equality
/// has to mean "the same declaration", not "the same object".
@Suite("Host entry")
nonisolated struct HostEntryTests {

    private static let file = URL(filePath: "/fabricated/keys/config")

    private static func entry(_ patterns: [String], ordinal: Int = 0) -> HostEntry {
        HostEntry(
            id: HostEntryID(file: file, ordinal: ordinal),
            lineRange: 0..<1,
            patterns: patterns.map(HostPattern.init(parsing:)),
            hostName: nil,
            user: nil,
            port: nil,
            identityFiles: [],
            repeatedKeywords: [],
            writability: .writable
        )
    }

    // MARK: - Patterns

    @Test("A pattern token is split into its text and its negation")
    func patternParsing() {
        let negated = HostPattern(parsing: "!bastion")
        #expect(negated.text == "bastion")
        #expect(negated.isNegated)
        #expect(!negated.hasWildcard)
        #expect(negated.token == "!bastion")

        let wildcard = HostPattern(parsing: "*.corp")
        #expect(wildcard.hasWildcard)
        #expect(!wildcard.isNegated)
        #expect(HostPattern(parsing: "db?").hasWildcard)
    }

    // MARK: - 2.10 pattern entries

    @Test("A block whose every pattern is wildcarded or negated is a pattern entry")
    func everyPatternWildcardedOrNegatedIsAPatternEntry() {
        #expect(Self.entry(["*"]).isPatternEntry)
        #expect(Self.entry(["*.corp", "!db.corp"]).isPatternEntry)
        #expect(Self.entry(["!bastion"]).isPatternEntry)
    }

    @Test("A block with one concrete pattern is a concrete host, whatever else it lists")
    func oneConcretePatternMakesAConcreteHost() {
        #expect(!Self.entry(["github.com"]).isPatternEntry)
        #expect(!Self.entry(["web", "*.corp"]).isPatternEntry)
    }

    @Test("The display name is the patterns as written, negation included")
    func displayName() {
        #expect(Self.entry(["web", "!db", "*.corp"]).displayName == "web !db *.corp")
    }

    @Test("Two entries with the same patterns in a different case are the same host")
    func hostIdentityIgnoresCase() {
        #expect(Self.entry(["GitHub.com"]).hostIdentity == Self.entry(["github.com"], ordinal: 1).hostIdentity)
        #expect(Self.entry(["a", "b"]).hostIdentity == Self.entry(["b", "a"]).hostIdentity)
        #expect(Self.entry(["a"]).hostIdentity != Self.entry(["!a"]).hostIdentity)
    }

    // MARK: - Value equality

    @Test("Entries are equal exactly when every declared value is")
    func entryEquality() {
        #expect(Self.entry(["web"]) == Self.entry(["web"]))
        #expect(Self.entry(["web"]) != Self.entry(["web"], ordinal: 1))
        #expect(Self.entry(["web"]) != Self.entry(["db"]))
    }

    @Test("A read-only downgrade changes only the writability")
    func downgradeKeepsEverythingElse() {
        let original = Self.entry(["web"])
        let downgraded = original.withWritability(.readOnly(.symbolicLinkOutsideDirectory))

        #expect(downgraded.writability == .readOnly(.symbolicLinkOutsideDirectory))
        #expect(downgraded.withWritability(.writable) == original)
    }

    @Test("Writability says why a file is read-only")
    func readOnlyReasons() {
        #expect(ConfigWritability.writable.readOnlyReason == nil)
        for reason in [ConfigReadOnlyReason.outsideDirectory, .notUTF8, .symbolicLinkOutsideDirectory] {
            #expect(ConfigWritability.readOnly(reason).readOnlyReason?.isEmpty == false)
        }
    }

    @Test("Keywords compare without regard to case, as OpenSSH reads them")
    func keywordsAreCaseInsensitive() {
        #expect(SSHConfigKeyword("HOSTNAME") == .hostName)
        #expect(SSHConfigKeyword("identityfile") == .identityFile)
        #expect(SSHConfigKeyword("Host") != .hostName)
    }
}
