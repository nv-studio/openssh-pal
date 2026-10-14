import Foundation
import Testing

/// The parser's one non-negotiable property is that it loses nothing: concatenating the lines
/// it produces reproduces the input bytes exactly. Every preservation guarantee downstream is
/// built on that.
@Suite("Configuration parser")
nonisolated struct SSHConfigParserTests {

    private static let url = URL(filePath: "/fabricated/keys/config")

    private static func parse(_ data: Data, writability: ConfigWritability = .writable) -> ParsedConfigFile {
        SSHConfigParser().parse(data, at: url, inclusionChain: [], writability: writability)
    }

    private static func parse(_ fixture: SSHConfigFixtures.Fixture) -> ParsedConfigFile {
        parse(fixture.data)
    }

    // MARK: - 13.5 round trip

    @Test("Concatenating the parsed lines reproduces every fixture byte for byte", arguments: SSHConfigFixtures.all)
    func roundTrip(_ fixture: SSHConfigFixtures.Fixture) {
        let file = Self.parse(fixture).file
        #expect(Data(file.lines.flatMap(\.bytes)) == fixture.data, "\(fixture.name)")
        #expect(file.original == fixture.data)
    }

    // MARK: - 9.2 line endings

    @Test("CRLF is recorded as a terminator, never left in the text")
    func crlfIsATerminator() {
        let file = Self.parse(SSHConfigFixtures.crlf).file

        #expect(file.lineTerminator == .crlf)
        #expect(file.lines.allSatisfy { $0.terminator == .crlf })
        #expect(file.lines.allSatisfy { !$0.text.unicodeScalars.contains("\r") })
        #expect(file.endsWithNewline)
    }

    @Test("A missing final newline is recorded on the last line")
    func missingFinalNewline() throws {
        let file = Self.parse(SSHConfigFixtures.noFinalNewline).file

        #expect(file.lineTerminator == .lf)
        #expect(try #require(file.lines.last).terminator == nil)
        #expect(try #require(file.lines.last).text == "    User bob")
        #expect(!file.endsWithNewline)
    }

    @Test("An empty file has no lines and counts as ending with a newline")
    func emptyFile() {
        let parsed = Self.parse(SSHConfigFixtures.empty)
        #expect(parsed.file.lines.isEmpty)
        #expect(parsed.file.endsWithNewline)
        #expect(parsed.entries.isEmpty)
    }

    @Test("A lone carriage return in the middle of a line stays in its text")
    func loneCarriageReturn() {
        let data = Data("Host a\rb\nUser x\r\n".utf8)
        let file = Self.parse(data).file

        #expect(file.lines.count == 2)
        #expect(file.lines[0].text == "Host a\rb")
        #expect(file.lines[0].terminator == .lf)
        #expect(file.lineTerminator == .lf)
        #expect(Data(file.lines.flatMap(\.bytes)) == data)
    }

    // MARK: - 2.1 / 2.2 / 2.11 entries

    @Test("One entry per Host block, in file order, with what each declares")
    func entriesInFileOrder() throws {
        let entries = Self.parse(SSHConfigFixtures.lf).entries

        #expect(entries.map(\.displayName) == ["bastion", "web"])

        let bastion = try #require(entries.first)
        #expect(bastion.id == HostEntryID(file: Self.url, ordinal: 0))
        #expect(bastion.lineRange == 0..<4)
        #expect(bastion.hostName == DeclaredValue(value: "bastion.example.com", line: 1))
        #expect(bastion.user == DeclaredValue(value: "alice", line: 2))
        #expect(bastion.port == nil)
        #expect(bastion.identityFiles.isEmpty)

        let web = try #require(entries.last)
        #expect(web.id.ordinal == 1)
        #expect(web.port == DeclaredValue(value: "2222", line: 6))
    }

    @Test("Separators, quotes and escapes are read as OpenSSH reads them")
    func valuesAreUnescaped() throws {
        let equals = try #require(Self.parse(SSHConfigFixtures.equalsSeparators).entries.first)
        #expect(equals.displayName == "bastion")
        #expect(equals.port?.value == "2222")

        let quoted = try #require(Self.parse(SSHConfigFixtures.quotes).entries.first)
        #expect(quoted.patterns == [HostPattern(text: "quoted alias", isNegated: false)])
        #expect(quoted.user?.value == "alice")
        #expect(quoted.identityFiles.map(\.value) == ["~/keys/my key"])
    }

    @Test("A Match block never becomes an entry")
    func matchBlocksAreNotEntries() {
        let parsed = Self.parse(SSHConfigFixtures.matchBlocks)

        #expect(parsed.entries.map(\.displayName) == ["bastion"])
        #expect(parsed.file.blocks.map(\.kind) == [.match, .host, .match])
    }

    @Test("A block's range stops at the next header, including a Match header")
    func blockRangesStopAtTheNextHeader() throws {
        let entry = try #require(Self.parse(SSHConfigFixtures.matchBlocks).entries.first)
        #expect(entry.lineRange == 3..<6)
    }

    @Test("Only what a block declares is recorded, never what a Host * block would supply")
    func declaredValuesOnly() throws {
        let bastion = try #require(Self.parse(SSHConfigFixtures.wildcardsFirst).entries.last)
        #expect(bastion.identityFiles.isEmpty)
        #expect(bastion.user == nil)
    }

    @Test("The first of a repeated value is the declared one, and the repetition is recorded")
    func repeatedKeywords() throws {
        let entry = try #require(Self.parse(SSHConfigFixtures.repeatedKeywords).entries.first)

        #expect(entry.hostName?.value == "first.example.com")
        #expect(entry.identityFiles.map(\.value) == ["~/keys/one", "~/keys/two"])
        #expect(entry.repeatedKeywords == [.hostName, .identityFile])
    }

    @Test("A pattern entry is recognised from its Host line")
    func patternEntries() throws {
        let entry = try #require(Self.parse(SSHConfigFixtures.wildcardsFirst).entries.first)
        #expect(entry.isPatternEntry)
    }

    // MARK: - 2.12 malformed lines

    @Test("Malformed lines are recorded by index, and the rest of the block is still read")
    func malformedLines() throws {
        let parsed = Self.parse(SSHConfigFixtures.malformed)

        #expect(parsed.malformedLines == [1, 2])
        let entry = try #require(parsed.entries.first)
        #expect(entry.port?.value == "22")
        #expect(entry.user == nil)
    }

    // MARK: - Includes

    @Test("A global Include is recorded with no condition")
    func globalInclude() {
        let includes = Self.parse(SSHConfigFixtures.globalInclude).includes
        #expect(includes == [IncludeDirective(line: 0, arguments: ["config.d/*"], condition: nil)])
    }

    @Test("An Include inside a Host block carries that block's patterns")
    func includeInsideHost() {
        let includes = Self.parse(SSHConfigFixtures.includeInHost).includes
        #expect(
            includes == [
                IncludeDirective(line: 1, arguments: ["corp.d/*"], condition: .host([HostPattern(parsing: "*.corp")])),
            ]
        )
    }

    @Test("An Include inside a Match block is conditional on something unknowable")
    func includeInsideMatch() {
        let includes = Self.parse(Data("Match all\n  Include x\n".utf8)).includes
        #expect(includes.first?.condition == .match)
    }

    // MARK: - Encoding and writability

    @Test("A file that is not UTF-8 is read-only, and its entries are still listed")
    func notUTF8() throws {
        let data = Data(Array("Host legacy\n    User ".utf8) + [0xFF, 0xFE] + Array("\n".utf8))
        let parsed = Self.parse(data)

        #expect(parsed.file.writability == .readOnly(.notUTF8))
        let entry = try #require(parsed.entries.first)
        #expect(entry.displayName == "legacy")
        #expect(entry.writability == .readOnly(.notUTF8))
    }

    @Test("Entries inherit their file's writability")
    func entriesInheritWritability() {
        let parsed = Self.parse(SSHConfigFixtures.lf.data, writability: .readOnly(.outsideDirectory))
        #expect(parsed.entries.allSatisfy { $0.writability == .readOnly(.outsideDirectory) })
    }
}
