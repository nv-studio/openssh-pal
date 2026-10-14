import Foundation
import Testing

/// The draft vocabulary is closed: every rejection names its field and carries words a user
/// can act on, and no combination the form cannot mean is expressible.
@Suite("Host draft vocabulary")
nonisolated struct HostDraftTests {

    @Test("An empty draft carries no values and keeps OpenSSH's default identities")
    func emptyDraft() {
        let draft = HostDraft.empty
        #expect(draft.patterns.isEmpty)
        #expect(draft.hostName.isEmpty)
        #expect(draft.user.isEmpty)
        #expect(draft.port.isEmpty)
        #expect(draft.keyChoice == .none)
    }

    @Test("Every draft error has a reason fit to show beside its field")
    func everyErrorHasAReason() {
        let errors: [HostDraftError] = [
            .empty,
            .notASingleConcreteHost,
            .duplicatesHost("github.com"),
            .portOutOfRange,
            .forbiddenCharacter(.lineBreak),
            .forbiddenCharacter(.hash),
            .forbiddenCharacter(.doubleQuote),
            .containsWhitespace,
        ]

        for error in errors {
            #expect(!error.reason.isEmpty)
        }
        #expect(HostDraftError.duplicatesHost("github.com").reason.contains("github.com"))
        #expect(HostDraftError.portOutOfRange.reason.contains("65535"))
        #expect(HostDraftError.forbiddenCharacter(.hash).reason.contains("#"))
    }

    @Test("Errors are keyed by field, so each message lands beside the value it concerns")
    func errorsAreKeyedByField() {
        let errors = HostDraftErrors(byField: [.port: .portOutOfRange])
        #expect(errors.byField[.port] == .portOutOfRange)
        #expect(errors.byField[.hostName] == nil)
    }

    @Test("Key choices are distinct values")
    func keyChoices() throws {
        let name = try #require(SSHKeyName.discovered("id_ed25519"))
        #expect(HostKeyChoice.unchanged != .none)
        #expect(HostKeyChoice.pair(name) == .pair(name))
        #expect(HostKeyChoice.pair(name) != .none)
    }

    @Test("Every load issue names the file it concerns and says what happened")
    func loadIssueMessages() {
        let file = URL(filePath: "/fabricated/keys/config")
        let issues: [ConfigLoadIssue] = [
            .unparseableLine(file: file, line: 3, reason: .invalidQuotes),
            .unreadable(file: file, .accessDenied(file)),
            .skippedInclude(file: file, line: 0, argument: "${HOME}/x", reason: .unresolvable(.environmentVariable)),
            .skippedInclude(file: file, line: 0, argument: "/etc/x", reason: .outsideOverride),
            .includeDepthExceeded(file: file),
            .includeCycle(file: file),
        ]

        for issue in issues {
            #expect(issue.file == file)
            #expect(issue.message.contains("config"))
        }
        // Lines are stored from zero and shown from one, as an editor numbers them.
        #expect(ConfigLoadIssue.unparseableLine(file: file, line: 3, reason: .invalidQuotes).message.contains("line 4"))
    }
}
