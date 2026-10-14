import Foundation
import Testing

/// Every value is judged before anything is written, so a typo cannot produce a configuration
/// `ssh` refuses to read. Each rejection is attached to the field it concerns.
@Suite("Host draft validator")
nonisolated struct HostDraftValidatorTests {

    private static let config = URL(filePath: "/fabricated/keys/config")

    private static let existing: [HostEntry] = SSHConfigParser().parse(
        Data(
            """
            Host github.com gh
                User git
            Host *.corp
            Host Bastion
            """.utf8
        ),
        at: config,
        inclusionChain: [],
        writability: .writable
    ).entries

    private static func draft(
        _ patterns: String,
        hostName: String = "",
        user: String = "",
        port: String = ""
    ) -> HostDraft {
        HostDraft(patterns: patterns, hostName: hostName, user: user, port: port, keyChoice: .none)
    }

    private static func errors(_ draft: HostDraft, mode: HostFormMode = .create) -> [HostDraftField: HostDraftError] {
        switch HostDraftValidator().validate(draft, mode: mode, existing: existing) {
        case .success: [:]
        case .failure(let errors): errors.byField
        }
    }

    // MARK: - Acceptance

    @Test("A complete, valid draft is accepted, trimmed, with empty values left undeclared")
    func validDraft() throws {
        let validated = try HostDraftValidator()
            .validate(Self.draft(" web ", hostName: " 10.0.0.5", user: "", port: "2222 "), mode: .create, existing: Self.existing)
            .get()

        #expect(validated.patterns == ["web"])
        #expect(validated.alias == "web")
        #expect(validated.hostName == "10.0.0.5")
        #expect(validated.user == nil)
        #expect(validated.port == "2222")
        #expect(validated.keyChoice == .none)
    }

    // MARK: - 7.1 / 7.2 alias

    @Test("An empty or whitespace-only alias is rejected", arguments: ["", "   ", "\t"])
    func emptyAlias(_ alias: String) {
        #expect(Self.errors(Self.draft(alias))[.patterns] == .empty)
    }

    @Test("On create, an alias with whitespace, a wildcard or a negation is rejected", arguments: ["two words", "*.corp", "db?", "!web"])
    func aliasMustBeOneConcreteHost(_ alias: String) {
        #expect(Self.errors(Self.draft(alias))[.patterns] == .notASingleConcreteHost)
    }

    // MARK: - 7.3 duplicates

    @Test("An alias matching another concrete entry's pattern is rejected, naming that entry, in any case")
    func duplicateAlias() {
        #expect(Self.errors(Self.draft("gh"))[.patterns] == .duplicatesHost("github.com gh"))
        #expect(Self.errors(Self.draft("GITHUB.COM"))[.patterns] == .duplicatesHost("github.com gh"))
        #expect(Self.errors(Self.draft("bastion"))[.patterns] == .duplicatesHost("Bastion"))
    }

    @Test("A name a pattern entry would match is not a duplicate; placement warns about it instead")
    func patternEntriesAreNotDuplicates() {
        #expect(Self.errors(Self.draft("db.corp"))[.patterns] == nil)
    }

    // MARK: - 7.4 / 7.5 / 7.6 values

    @Test("A port outside 1–65535, or not a whole number, is rejected stating the range", arguments: ["0", "65536", "-1", "22.5", "ssh", "+22"])
    func portOutOfRange(_ port: String) {
        #expect(Self.errors(Self.draft("web", port: port))[.port] == .portOutOfRange)
    }

    @Test("The ends of the port range are accepted", arguments: ["1", "65535", "22"])
    func portInRange(_ port: String) {
        #expect(Self.errors(Self.draft("web", port: port))[.port] == nil)
    }

    @Test(
        "A line break, # or double quote is rejected in any value, naming the character",
        arguments: [
            ("a\nb", HostDraftError.ForbiddenCharacter.lineBreak),
            ("a\rb", .lineBreak),
            ("a#b", .hash),
            ("a\"b", .doubleQuote),
        ]
    )
    func forbiddenCharacters(_ value: String, _ character: HostDraftError.ForbiddenCharacter) {
        let errors = Self.errors(Self.draft(value, hostName: value, user: value, port: value))
        for field in HostDraftField.allCases {
            #expect(errors[field] == .forbiddenCharacter(character), "\(field)")
        }
    }

    @Test("A host name or user containing whitespace is rejected")
    func whitespaceInValues() {
        let errors = Self.errors(Self.draft("web", hostName: "a b", user: "al\tice"))
        #expect(errors[.hostName] == .containsWhitespace)
        #expect(errors[.user] == .containsWhitespace)
    }

    @Test("Characters that only need quoting are accepted and left to the formatter")
    func quotableCharactersAreAccepted() {
        #expect(Self.errors(Self.draft("web", hostName: #"back\slash"#, user: "o'brien")).isEmpty)
    }

    @Test("Every rejection is reported at once, each beside its own field")
    func everyFieldAtOnce() {
        let errors = Self.errors(Self.draft("", hostName: "a b", user: "#", port: "0"))
        #expect(errors == [.patterns: .empty, .hostName: .containsWhitespace, .user: .forbiddenCharacter(.hash), .port: .portOutOfRange])
    }

    // MARK: - 7.9 edit mode

    @Test("An edit may keep patterns the block already declares, wildcards and negations included")
    func editKeepsDeclaredPatterns() throws {
        let corp = try #require(Self.existing.first { $0.displayName == "*.corp" })
        #expect(Self.errors(Self.draft("*.corp", user: "u"), mode: .edit(corp)).isEmpty)

        let validated = try HostDraftValidator().validate(Self.draft("*.corp  lan"), mode: .edit(corp), existing: Self.existing).get()
        #expect(validated.patterns == ["*.corp", "lan"])
    }

    @Test("An edit may not add a new wildcard or negation")
    func editRejectsNewWildcards() throws {
        let corp = try #require(Self.existing.first { $0.displayName == "*.corp" })
        #expect(Self.errors(Self.draft("*.corp *.lan"), mode: .edit(corp))[.patterns] == .notASingleConcreteHost)
    }

    @Test("An edit is not a duplicate of itself, but is of another entry")
    func editExcludesItself() throws {
        let github = try #require(Self.existing.first)
        #expect(Self.errors(Self.draft("github.com gh", hostName: "x"), mode: .edit(github)).isEmpty)
        #expect(Self.errors(Self.draft("github.com gh bastion"), mode: .edit(github))[.patterns] == .duplicatesHost("Bastion"))
    }

    @Test("Every value rule applies to an edit as it does to a creation")
    func editAppliesValueRules() throws {
        let github = try #require(Self.existing.first)
        let errors = Self.errors(Self.draft("github.com gh", hostName: "a b", user: "\"", port: "99999"), mode: .edit(github))
        #expect(errors == [.hostName: .containsWhitespace, .user: .forbiddenCharacter(.doubleQuote), .port: .portOutOfRange])
    }
}
