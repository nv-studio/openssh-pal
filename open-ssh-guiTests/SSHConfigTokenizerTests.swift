import Foundation
import Testing

/// The tokenizer decides which bytes an edit replaces, so it has to read a line exactly as
/// OpenSSH's `process_config_line` and `argv_split(…, terminate_on_comment = 1)` do. A misread
/// here would rewrite the wrong text. Every case below is derived from those two functions.
@Suite("Configuration tokenizer")
nonisolated struct SSHConfigTokenizerTests {

    private static let tokenizer = SSHConfigTokenizer()

    /// The directive a line holds, failing the test when it holds something else.
    private static func directive(_ line: String) throws -> SSHConfigDirective {
        guard case .directive(let directive) = tokenizer.tokenize(line) else {
            Issue.record("\(line.debugDescription) is not a directive: \(tokenizer.tokenize(line))")
            throw CancellationError()
        }
        return directive
    }

    private static func slice(_ line: String, _ span: Range<String.Index>) -> String {
        String(line.unicodeScalars[span])
    }

    // MARK: - Blank and comment lines

    @Test("Empty and whitespace-only lines are blank", arguments: ["", "   ", "\t", " \t ", "\u{0C}"])
    func blankLines(_ line: String) {
        #expect(Self.tokenizer.tokenize(line) == .blank)
    }

    @Test("A line whose first token starts with # is a comment", arguments: ["#", "# comment", "   # indented", "\t#tab", "#Host x"])
    func commentLines(_ line: String) {
        #expect(Self.tokenizer.tokenize(line) == .comment)
    }

    // MARK: - Keywords and separators

    @Test(
        "Whitespace, or optional whitespace and one =, separates the keyword",
        arguments: [
            ("Host bastion", "Host", "bastion"),
            ("Host=bastion", "Host", "bastion"),
            ("HostName = bastion", "HostName", "bastion"),
            ("User= alice", "User", "alice"),
            ("Port =2222", "Port", "2222"),
            ("Port\t\t22", "Port", "22"),
        ]
    )
    func separators(_ line: String, _ keyword: String, _ argument: String) throws {
        let directive = try Self.directive(line)
        #expect(directive.keyword == SSHConfigKeyword(keyword))
        #expect(directive.arguments == [argument])
        #expect(Self.slice(line, directive.keywordSpan) == keyword)
        #expect(Self.slice(line, directive.argumentSpan) == argument)
    }

    @Test("Only one = is a separator; a second belongs to the argument")
    func onlyOneEquals() throws {
        #expect(try Self.directive("Host==x").arguments == ["=x"])
        #expect(try Self.directive("Host = =x").arguments == ["=x"])
    }

    @Test("Keywords are compared without case, and keep their spelling in the span")
    func keywordCase() throws {
        let line = "    HOSTNAME example.com"
        let directive = try Self.directive(line)

        #expect(directive.keyword == .hostName)
        #expect(Self.slice(line, directive.keywordSpan) == "HOSTNAME")
        #expect(Self.slice(line, directive.indentation) == "    ")
    }

    // MARK: - Arguments

    @Test("Several arguments are split on whitespace, and the span covers them all")
    func severalArguments() throws {
        let line = "Host web  db\t*.corp"
        let directive = try Self.directive(line)

        #expect(directive.arguments == ["web", "db", "*.corp"])
        #expect(Self.slice(line, directive.argumentSpan) == "web  db\t*.corp")
    }

    @Test(
        "Both quote styles group a run, and are removed from the argument",
        arguments: [
            (#"IdentityFile "~/keys/my key""#, "~/keys/my key"),
            ("User 'alice'", "alice"),
            (#"User a"b c"d"#, "ab cd"),
            (#"User "it's""#, "it's"),
            (#"User '"quoted"'"#, #""quoted""#),
            (#"User """#, ""),
        ]
    )
    func quotes(_ line: String, _ argument: String) throws {
        #expect(try Self.directive(line).arguments == [argument])
    }

    @Test(
        "Backslash escapes a quote, a backslash and, outside quotes, a space; any other backslash is literal",
        arguments: [
            (#"IdentityFile with\ space"#, "with space"),
            (#"User a\"b"#, #"a"b"#),
            (#"User a\'b"#, "a'b"),
            (#"User a\\b"#, #"a\b"#),
            (#"HostName literal\back"#, #"literal\back"#),
            (#"User "a\"b""#, #"a"b"#),
            (#"User "a\ b""#, #"a\ b"#),
            (#"User trailing\"#, #"trailing\"#),
        ]
    )
    func escapes(_ line: String, _ argument: String) throws {
        #expect(try Self.directive(line).arguments == [argument])
    }

    @Test("A token starting with # ends the line, and the span stops before it")
    func trailingComment() throws {
        let line = "    User alice   # work account"
        let directive = try Self.directive(line)

        #expect(directive.arguments == ["alice"])
        #expect(Self.slice(line, directive.argumentSpan) == "alice")
    }

    @Test("A # inside a token is part of it, because only a token's start ends the line")
    func hashInsideAToken() throws {
        #expect(try Self.directive("User a#b").arguments == ["a#b"])
        #expect(try Self.directive("User a #b c").arguments == ["a"])
    }

    @Test("Trailing whitespace and a final form feed are stripped before reading")
    func trailingWhitespace() throws {
        let line = "Host bastion  \t\u{0C}"
        let directive = try Self.directive(line)

        #expect(directive.arguments == ["bastion"])
        #expect(Self.slice(line, directive.argumentSpan) == "bastion")
    }

    @Test("Non-ASCII text is read, and spans land on scalar boundaries")
    func nonASCII() throws {
        let line = "  User jürgen # café"
        let directive = try Self.directive(line)

        #expect(directive.arguments == ["jürgen"])
        #expect(Self.slice(line, directive.argumentSpan) == "jürgen")
    }

    // MARK: - Malformed lines

    @Test("An unterminated quote is malformed, as OpenSSH's invalid quotes")
    func unterminatedQuote() {
        #expect(Self.tokenizer.tokenize(#"User "unterminated"#) == .malformed(.invalidQuotes))
        #expect(Self.tokenizer.tokenize("User 'a b") == .malformed(.invalidQuotes))
    }

    @Test("A keyword with no argument is malformed", arguments: ["HostName", "HostName   ", "HostName # nothing", "Port ="])
    func missingArgument(_ line: String) {
        #expect(Self.tokenizer.tokenize(line) == .malformed(.missingArgument))
    }

    @Test("A line that starts with a separator has no keyword")
    func missingKeyword() {
        #expect(Self.tokenizer.tokenize("= value") == .malformed(.missingKeyword))
    }
}
