import Foundation
import Testing

/// A user must not be able to tell from the file that a GUI touched it. Every test here checks
/// that the change lands exactly where it should and that every other line survives.
@Suite("Host block editor")
nonisolated struct HostBlockEditorTests {

    private static let home = URL(filePath: "/fabricated/home")
    private static let keys = URL(filePath: "/fabricated/keys")
    private static let config = keys.appending(path: "config")
    private static let editor = HostBlockEditor()

    private static let overrideContext = IdentityResolutionContext(
        homeDirectory: home,
        sshDirectory: SSHDirectory(url: keys),
        userName: "alice",
        defaultDirectory: home.appending(path: SSHDirectoryResolver.directoryName)
    )

    private static let defaultContext = IdentityResolutionContext(
        homeDirectory: home,
        sshDirectory: SSHDirectory(url: home.appending(path: SSHDirectoryResolver.directoryName)),
        userName: "alice",
        defaultDirectory: home.appending(path: SSHDirectoryResolver.directoryName)
    )

    private static func parse(_ data: Data) -> ParsedConfigFile {
        SSHConfigParser().parse(data, at: config, inclusionChain: [], writability: .writable)
    }

    private static func parse(_ text: String) -> ParsedConfigFile {
        parse(Data(text.utf8))
    }

    private static func parse(_ fixture: SSHConfigFixtures.Fixture) -> ParsedConfigFile {
        parse(fixture.data)
    }

    private static func texts(_ data: Data) -> [String] {
        parse(data).file.lines.map(\.text)
    }

    private static func string(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    /// A validated draft that declares exactly what `entry` declares, keys left unchanged.
    private static func unchangedDraft(for entry: HostEntry) -> ValidatedHostDraft {
        ValidatedHostDraft(
            patterns: entry.patterns.map(\.token),
            hostName: entry.hostName?.value,
            user: entry.user?.value,
            port: entry.port?.value,
            keyChoice: .unchanged
        )
    }

    private static func draft(
        _ patterns: [String],
        hostName: String? = nil,
        user: String? = nil,
        port: String? = nil,
        key: HostKeyChoice = .none
    ) -> ValidatedHostDraft {
        ValidatedHostDraft(patterns: patterns, hostName: hostName, user: user, port: port, keyChoice: key)
    }

    private static func name(_ raw: String) -> SSHKeyName { SSHKeyName.discovered(raw)! }

    // MARK: - 13.6 edits leave every other line alone

    @Test("Saving an entry unchanged reproduces the file byte for byte", arguments: SSHConfigFixtures.all)
    func unchangedEditIsANoOp(_ fixture: SSHConfigFixtures.Fixture) {
        let parsed = Self.parse(fixture.data)
        for entry in parsed.entries {
            let result = Self.editor.applying(Self.unchangedDraft(for: entry), to: entry, in: parsed.file, context: Self.overrideContext)
            #expect(result == fixture.data, "\(fixture.name): \(entry.displayName)")
        }
    }

    @Test("Editing one entry leaves every line outside its block identical and in order", arguments: SSHConfigFixtures.all)
    func editStaysInsideTheBlock(_ fixture: SSHConfigFixtures.Fixture) {
        let parsed = Self.parse(fixture.data)
        let original = parsed.file.lines.map(\.text)

        for entry in parsed.entries {
            let draft = Self.unchangedDraft(for: entry)
            let edited = ValidatedHostDraft(
                patterns: draft.patterns,
                hostName: "changed.example.com",
                user: draft.user == nil ? "added" : nil,
                port: "2200",
                keyChoice: .pair(Self.name("id_new"))
            )
            let result = Self.texts(Self.editor.applying(edited, to: entry, in: parsed.file, context: Self.overrideContext))

            let before = entry.lineRange.lowerBound
            let after = original.count - entry.lineRange.upperBound
            #expect(Array(result.prefix(before)) == Array(original.prefix(before)), "\(fixture.name): \(entry.displayName)")
            #expect(Array(result.suffix(after)) == Array(original.suffix(after)), "\(fixture.name): \(entry.displayName)")
        }
    }

    // MARK: - 5.2 a changed value rewrites only its argument

    @Test("A changed value keeps the line's indentation, keyword spelling, separator and trailing comment")
    func valueEditKeepsTheRestOfTheLine() throws {
        let parsed = Self.parse(SSHConfigFixtures.trailingComments)
        let entry = try #require(parsed.entries.first)

        let result = Self.editor.applying(
            Self.draft(["bastion"], hostName: "jump.example.com", user: "alice"),
            to: entry,
            in: parsed.file,
            context: Self.overrideContext
        )

        #expect(Self.string(result) == """
            # Personal machines
            Host bastion # the jump host
                HostName jump.example.com   # resolved by DNS
                User alice # work account

            """)
    }

    @Test("= separators and keyword case survive an edit")
    func separatorsSurvive() throws {
        let parsed = Self.parse("Host=bastion\n  HOSTNAME = old.example.com\n  user= alice\n")
        let entry = try #require(parsed.entries.first)

        let result = Self.editor.applying(
            Self.draft(["bastion"], hostName: "new.example.com", user: "bob"),
            to: entry,
            in: parsed.file,
            context: Self.overrideContext
        )

        #expect(Self.string(result) == "Host=bastion\n  HOSTNAME = new.example.com\n  user= bob\n")
    }

    @Test("A value that needs quoting is written quoted")
    func quotedValue() throws {
        let parsed = Self.parse("Host a\n    User x\n")
        let entry = try #require(parsed.entries.first)

        let result = Self.editor.applying(Self.draft(["a"], user: "o'brien"), to: entry, in: parsed.file, context: Self.overrideContext)
        #expect(Self.string(result) == "Host a\n    User \"o'brien\"\n")
    }

    // MARK: - 5.3 / 5.4 clearing and adding

    @Test("Clearing a value removes its directive")
    func clearingRemovesTheLine() throws {
        let parsed = Self.parse(SSHConfigFixtures.lf)
        let entry = try #require(parsed.entries.first)

        let result = Self.editor.applying(Self.draft(["bastion"], hostName: "bastion.example.com"), to: entry, in: parsed.file, context: Self.overrideContext)
        #expect(Self.string(result).hasPrefix("Host bastion\n    HostName bastion.example.com\n\nHost web\n"))
    }

    @Test("A new value is added after the block's last directive, before its trailing blank line")
    func addingInsertsAfterTheLastDirective() throws {
        let parsed = Self.parse(SSHConfigFixtures.lf)
        let entry = try #require(parsed.entries.first)

        let result = Self.editor.applying(
            Self.draft(["bastion"], hostName: "bastion.example.com", user: "alice", port: "22"),
            to: entry,
            in: parsed.file,
            context: Self.overrideContext
        )
        #expect(Self.string(result).hasPrefix("Host bastion\n    HostName bastion.example.com\n    User alice\n    Port 22\n\nHost web\n"))
    }

    @Test("A new value goes before comments that trail the block")
    func addingGoesBeforeTrailingComments() throws {
        let parsed = Self.parse("Host a\n  User x\n  # disabled: Port 1\n\n# about b\nHost b\n")
        let entry = try #require(parsed.entries.first)

        let result = Self.editor.applying(Self.draft(["a"], user: "x", port: "22"), to: entry, in: parsed.file, context: Self.overrideContext)
        #expect(Self.string(result) == "Host a\n  User x\n  Port 22\n  # disabled: Port 1\n\n# about b\nHost b\n")
    }

    @Test("A new directive uses the block's indentation, then the file's, then four spaces")
    func indentationFallbacks() throws {
        let tabs = Self.parse(SSHConfigFixtures.tabs)
        let web = try #require(tabs.entries.last)
        let tabbed = Self.editor.applying(Self.draft(["web"], user: "u", port: "22"), to: web, in: tabs.file, context: Self.overrideContext)
        #expect(Self.string(tabbed).hasSuffix("Host web\n\tPort 22\n\tUser u\n"))

        let fileWide = Self.parse("Host a\n  User x\nHost b\n")
        let b = try #require(fileWide.entries.last)
        let fromFile = Self.editor.applying(Self.draft(["b"], user: "y"), to: b, in: fileWide.file, context: Self.overrideContext)
        #expect(Self.string(fromFile) == "Host a\n  User x\nHost b\n  User y\n")

        let bare = Self.parse("Host a\n")
        let a = try #require(bare.entries.first)
        let fallback = Self.editor.applying(Self.draft(["a"], user: "y"), to: a, in: bare.file, context: Self.overrideContext)
        #expect(Self.string(fallback) == "Host a\n    User y\n")
    }

    // MARK: - 9.2 line endings

    @Test("Added lines take the file's CRLF terminator, and other lines keep theirs")
    func crlfIsPreserved() throws {
        let parsed = Self.parse(SSHConfigFixtures.crlf)
        let entry = try #require(parsed.entries.last)

        let result = Self.editor.applying(Self.draft(["web"], hostName: "web.local", port: "2222"), to: entry, in: parsed.file, context: Self.overrideContext)
        #expect(Self.string(result).hasSuffix("Host web\r\n    Port 2222\r\n    HostName web.local\r\n"))
        #expect(!Self.string(result).replacingOccurrences(of: "\r\n", with: "").contains("\n"))
    }

    @Test("A file with no final newline still has none after an edit to its last block")
    func noFinalNewlineIsPreserved() throws {
        let parsed = Self.parse(SSHConfigFixtures.noFinalNewline)
        let entry = try #require(parsed.entries.last)

        let result = Self.editor.applying(Self.draft(["web"], hostName: "web.local", user: "bob"), to: entry, in: parsed.file, context: Self.overrideContext)
        #expect(Self.string(result).hasSuffix("Host web\n    User bob\n    HostName web.local"))
    }

    // MARK: - Patterns

    @Test("The Host line is rewritten only when the patterns change, keeping its comment")
    func patternsRewriteTheHostLine() throws {
        let parsed = Self.parse(SSHConfigFixtures.trailingComments)
        let entry = try #require(parsed.entries.first)
        var draft = Self.unchangedDraft(for: entry)
        draft = ValidatedHostDraft(patterns: ["jump", "bastion"], hostName: draft.hostName, user: draft.user, port: nil, keyChoice: .unchanged)

        let result = Self.texts(Self.editor.applying(draft, to: entry, in: parsed.file, context: Self.overrideContext))
        #expect(result[1] == "Host jump bastion # the jump host")
    }

    // MARK: - 5.5 / 5.6 directives the form does not present, and identity files

    @Test("Directives the form does not present keep their value, position and comments")
    func unknownDirectivesSurvive() throws {
        let parsed = Self.parse(SSHConfigFixtures.unknownKeywords)
        let entry = try #require(parsed.entries.first)

        let result = Self.editor.applying(Self.draft(["mac"], hostName: "mac.lan", user: "me"), to: entry, in: parsed.file, context: Self.overrideContext)
        #expect(Self.string(result) == """
            IgnoreUnknown UseKeychain
            Host mac
                UseKeychain yes
                AddKeysToAgent yes
                HostName mac.lan
                FutureOption whatever value
                User me

            """)
    }

    @Test("An unchanged key choice leaves every IdentityFile line alone")
    func unchangedKeys() throws {
        let parsed = Self.parse(SSHConfigFixtures.repeatedKeywords)
        let entry = try #require(parsed.entries.first)

        let result = Self.editor.applying(
            Self.draft(["twice"], hostName: "first.example.com", user: "u", key: .unchanged),
            to: entry,
            in: parsed.file,
            context: Self.overrideContext
        )
        #expect(Self.texts(result).filter { $0.contains("IdentityFile") } == ["    IdentityFile ~/keys/one", "    IdentityFile ~/keys/two"])
    }

    @Test("Choosing no key removes every IdentityFile line")
    func noKeyRemovesThemAll() throws {
        let parsed = Self.parse(SSHConfigFixtures.repeatedKeywords)
        let entry = try #require(parsed.entries.first)

        let result = Self.editor.applying(Self.draft(["twice"], hostName: "first.example.com"), to: entry, in: parsed.file, context: Self.overrideContext)
        #expect(!Self.string(result).contains("IdentityFile"))
        #expect(Self.string(result).contains("HostName second.example.com"))
    }

    @Test("Choosing a key inserts an IdentityFile, in tilde form in the default directory")
    func choosingAKeyInserts() throws {
        let parsed = Self.parse("Host a\n    User x\n")
        let entry = try #require(parsed.entries.first)

        let result = Self.editor.applying(Self.draft(["a"], user: "x", key: .pair(Self.name("id_work"))), to: entry, in: parsed.file, context: Self.defaultContext)
        #expect(Self.string(result) == "Host a\n    User x\n    IdentityFile ~/" + SSHDirectoryResolver.directoryName + "/id_work\n")
    }

    @Test("Choosing a key replaces a single IdentityFile's value, keeping its line")
    func choosingAKeyReplacesOne() throws {
        let parsed = Self.parse("Host a\n    IdentityFile ~/old   # previous\n    User x\n")
        let entry = try #require(parsed.entries.first)

        let result = Self.editor.applying(Self.draft(["a"], user: "x", key: .pair(Self.name("id_work"))), to: entry, in: parsed.file, context: Self.overrideContext)
        #expect(Self.string(result) == "Host a\n    IdentityFile /fabricated/keys/id_work   # previous\n    User x\n")
    }

    @Test("Explicitly choosing a key over several IdentityFile lines keeps one and removes the rest")
    func choosingAKeyReplacesSeveral() throws {
        let parsed = Self.parse(SSHConfigFixtures.repeatedKeywords)
        let entry = try #require(parsed.entries.first)

        let result = Self.editor.applying(
            Self.draft(["twice"], hostName: "first.example.com", key: .pair(Self.name("id_work"))),
            to: entry,
            in: parsed.file,
            context: Self.overrideContext
        )
        #expect(Self.texts(result).filter { $0.contains("IdentityFile") } == ["    IdentityFile /fabricated/keys/id_work"])
    }

    // MARK: - 6.5 / 6.11 inserting a block

    @Test("A block appended to a file is separated from the last block by one blank line")
    func appendSeparatesWithOneBlank() {
        let parsed = Self.parse(SSHConfigFixtures.lf)
        let result = Self.editor.inserting(
            Self.draft(["new"], hostName: "new.example.com", user: "u", port: "22", key: .pair(Self.name("id_work"))),
            at: .end,
            in: parsed.file,
            context: Self.overrideContext
        )

        #expect(Self.string(result) == SSHConfigFixtures.lf.text + """

            Host new
                HostName new.example.com
                User u
                Port 22
                IdentityFile /fabricated/keys/id_work

            """)
    }

    @Test("Only supplied directives are written, and an existing trailing blank is reused")
    func appendAfterATrailingBlank() {
        let parsed = Self.parse("Host a\n\n")
        let result = Self.editor.inserting(Self.draft(["b"]), at: .end, in: parsed.file, context: Self.overrideContext)
        #expect(Self.string(result) == "Host a\n\nHost b\n")
    }

    @Test("A block inserted before another is followed by one blank line, and preceded by one when needed")
    func insertBefore() {
        let tight = Self.parse("Host a\nHost *\n    User x\n")
        #expect(
            Self.string(Self.editor.inserting(Self.draft(["new"]), at: .before(line: 1), in: tight.file, context: Self.overrideContext))
                == "Host a\n\nHost new\n\nHost *\n    User x\n"
        )

        let spaced = Self.parse("Host a\n\nHost *\n")
        #expect(
            Self.string(Self.editor.inserting(Self.draft(["new"]), at: .before(line: 2), in: spaced.file, context: Self.overrideContext))
                == "Host a\n\nHost new\n\nHost *\n"
        )

        let first = Self.parse("Host *\n")
        #expect(
            Self.string(Self.editor.inserting(Self.draft(["new"]), at: .before(line: 0), in: first.file, context: Self.overrideContext))
                == "Host new\n\nHost *\n"
        )
    }

    @Test("A new block follows the file's indentation and line endings, and its final-newline state")
    func insertFollowsTheFilesStyle() {
        let tabs = Self.parse(SSHConfigFixtures.tabs)
        #expect(Self.string(Self.editor.inserting(Self.draft(["n"], user: "u"), at: .end, in: tabs.file, context: Self.overrideContext)).hasSuffix("\nHost n\n\tUser u\n"))

        let crlf = Self.parse(SSHConfigFixtures.crlf)
        #expect(Self.string(Self.editor.inserting(Self.draft(["n"], user: "u"), at: .end, in: crlf.file, context: Self.overrideContext)).hasSuffix("\r\n\r\nHost n\r\n    User u\r\n"))

        let open = Self.parse(SSHConfigFixtures.noFinalNewline)
        #expect(Self.string(Self.editor.inserting(Self.draft(["n"], user: "u"), at: .end, in: open.file, context: Self.overrideContext)).hasSuffix("    User bob\n\nHost n\n    User u"))
    }

    @Test("Inserting leaves every original line in place, for every fixture", arguments: SSHConfigFixtures.all)
    func insertPreservesEveryLine(_ fixture: SSHConfigFixtures.Fixture) {
        let parsed = Self.parse(fixture.data)
        let original = parsed.file.lines.map(\.text)
        let result = Self.texts(Self.editor.inserting(Self.draft(["n"], user: "u"), at: .end, in: parsed.file, context: Self.overrideContext))
        #expect(Array(result.prefix(original.count)) == original, "\(fixture.name)")
    }

    @Test("A brand-new file holds only the new block")
    func newFile() {
        let result = Self.editor.newFile(containing: Self.draft(["n"], hostName: "n.example.com", port: "22"), context: Self.overrideContext)
        #expect(Self.string(result) == "Host n\n    HostName n.example.com\n    Port 22\n")
    }

    // MARK: - 8.3 removing a block

    @Test("Removing the first block takes the blank after it, so no leading blank is left")
    func removeFirst() throws {
        let parsed = Self.parse(SSHConfigFixtures.lf)
        let result = Self.editor.removing(try #require(parsed.entries.first), from: parsed.file)
        #expect(Self.string(result) == "Host web\n    HostName 10.0.0.5\n    Port 2222\n")
    }

    @Test("Removing the last block takes the blank before it, so no trailing blank is left")
    func removeLast() throws {
        let parsed = Self.parse(SSHConfigFixtures.lf)
        let result = Self.editor.removing(try #require(parsed.entries.last), from: parsed.file)
        #expect(Self.string(result) == "Host bastion\n    HostName bastion.example.com\n    User alice\n")
    }

    @Test("Removing a block takes its attached comments and leaves exactly one blank between neighbours")
    func removeMiddleWithAttachedComments() throws {
        let parsed = Self.parse("Host a\n    User x\n\n# about b\n# more about b\nHost b\n    User y\n\nHost c\n")
        let result = Self.editor.removing(parsed.entries[1], from: parsed.file)
        #expect(Self.string(result) == "Host a\n    User x\n\nHost c\n")
    }

    @Test("A comment separated from the Host line by a blank, or indented, is not attached")
    func unattachedCommentsStay() throws {
        let parsed = Self.parse("# file header\n\nHost a\n    User x\n")
        #expect(Self.string(Self.editor.removing(parsed.entries[0], from: parsed.file)) == "# file header\n")
    }

    @Test("The next block's attached comments are not taken with the block above them")
    func nextBlocksCommentsStay() throws {
        let parsed = Self.parse("Host a\n    User x\n# about b\nHost b\n")
        #expect(Self.string(Self.editor.removing(parsed.entries[0], from: parsed.file)) == "# about b\nHost b\n")
    }

    @Test("Removing the last block of a file with no final newline leaves none")
    func removeKeepsMissingFinalNewline() throws {
        let parsed = Self.parse(SSHConfigFixtures.noFinalNewline)
        let result = Self.editor.removing(try #require(parsed.entries.last), from: parsed.file)
        #expect(Self.string(result) == "Host bastion\n    HostName bastion.example.com")
    }

    @Test("Removal leaves every other line in order, for every fixture", arguments: SSHConfigFixtures.all)
    func removePreservesEveryOtherLine(_ fixture: SSHConfigFixtures.Fixture) {
        let parsed = Self.parse(fixture.data)
        let original = parsed.file.lines.map(\.text)

        for entry in parsed.entries {
            let result = Self.texts(Self.editor.removing(entry, from: parsed.file))

            // Everything left is an original line, in its original order.
            var cursor = original.startIndex
            for line in result {
                guard let found = original[cursor...].firstIndex(of: line) else {
                    Issue.record("\(fixture.name): \(line.debugDescription) is not an original line in order")
                    break
                }
                cursor = found + 1
            }
            #expect(!result.contains(original[entry.headerLine]), "\(fixture.name): the Host line survived")
            #expect(result.count < original.count)
        }
    }
}
