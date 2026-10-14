import Foundation
import Testing

/// A written value must read back as exactly the value the user typed. The property is checked
/// by feeding every formatted value through the same tokenizer that reads the file.
@Suite("Configuration value formatter")
nonisolated struct SSHConfigValueFormatterTests {

    private static let formatter = SSHConfigValueFormatter()
    private static let home = URL(filePath: "/fabricated/home")
    private static let defaultDirectory = home.appending(path: SSHDirectoryResolver.directoryName)

    private static func context(_ directory: URL) -> IdentityResolutionContext {
        IdentityResolutionContext(
            homeDirectory: home,
            sshDirectory: SSHDirectory(url: directory),
            userName: "alice",
            defaultDirectory: defaultDirectory
        )
    }

    /// What OpenSSH would read back from `Keyword <formatted>`.
    private static func readBack(_ formatted: String) -> [String]? {
        guard case .directive(let directive) = SSHConfigTokenizer().tokenize("    User " + formatted + "  # note") else {
            return nil
        }
        return directive.arguments
    }

    @Test("A plain value is written bare")
    func bare() {
        #expect(Self.formatter.argument(for: "bastion.example.com") == "bastion.example.com")
        #expect(Self.formatter.argument(for: "~/keys/id_ed25519") == "~/keys/id_ed25519")
        #expect(Self.formatter.argument(for: "a#b") == "a#b")
    }

    @Test("Whitespace, a quote, a backslash or a leading = or # is quoted, with backslashes escaped")
    func quoted() {
        #expect(Self.formatter.argument(for: "my key") == #""my key""#)
        #expect(Self.formatter.argument(for: "o'brien") == #""o'brien""#)
        #expect(Self.formatter.argument(for: #"a\b"#) == #""a\\b""#)
        #expect(Self.formatter.argument(for: "=x") == #""=x""#)
        #expect(Self.formatter.argument(for: "#x") == ##""#x""##)
        #expect(Self.formatter.argument(for: "") == #""""#)
    }

    @Test("Every formatted value tokenizes back to exactly the value, over a generated corpus")
    func roundTripProperty() {
        // A small deterministic generator: reproducible on every run, and broad enough to put
        // every awkward character at the start, the middle and the end of a value.
        let alphabet: [String] = ["a", "Z", "0", " ", "\t", "'", "\\", "=", "#", "é", "%", "~", "/", "!", "*", "\""]
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15

        func next() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 33)
        }

        for _ in 0..<2000 {
            let length = 1 + next() % 8
            let value = (0..<length).map { _ in alphabet[next() % alphabet.count] }.joined()
            #expect(Self.readBack(Self.formatter.argument(for: value)) == [value], "\(value.debugDescription)")
        }
    }

    @Test("In the default directory a chosen key is written in tilde form")
    func tildeFormInTheDefaultDirectory() throws {
        let name = try #require(SSHKeyName.discovered("id_work"))
        let argument = Self.formatter.identityFileArgument(for: name, context: Self.context(Self.defaultDirectory))
        #expect(argument == "~/" + SSHDirectoryResolver.directoryName + "/id_work")
    }

    @Test("Under an override a chosen key is written as its absolute private key path, quoted if needed")
    func absolutePathUnderAnOverride() throws {
        let context = Self.context(URL(filePath: "/fabricated/my keys"))
        let name = try #require(SSHKeyName.discovered("id_work"))
        let argument = Self.formatter.identityFileArgument(for: name, context: context)

        #expect(argument == #""/fabricated/my keys/id_work""#)
        #expect(Self.readBack(argument) == ["/fabricated/my keys/id_work"])
    }
}
