import Foundation
import Testing

/// `Include` globs are expanded with glob(3). The leading-dot rule matters most: it is what
/// keeps `Include config.d/*` from reading the app's own hidden backup and temporary files.
@Suite("Glob pattern")
nonisolated struct GlobPatternTests {

    @Test(
        "Wildcards match as glob(3) does",
        arguments: [
            ("*", "work", true),
            ("*.conf", "work.conf", true),
            ("*.conf", "work.config", false),
            ("w?rk", "work", true),
            ("w?rk", "wrk", false),
            ("[wb]ork", "bork", true),
            ("[!w]ork", "work", false),
            ("[!w]ork", "fork", true),
            ("[a-c]x", "bx", true),
            ("[a-c]x", "dx", false),
            ("work", "work", true),
            ("work", "Work", false),
            (#"\*"#, "*", true),
            (#"\*"#, "a", false),
            ("a*b*c", "aXbYc", true),
            ("a*b*c", "aXbY", false),
            ("[ab", "[ab", true),
        ]
    )
    func wildcards(_ pattern: String, _ name: String, _ expected: Bool) {
        #expect(GlobPattern(pattern).matches(name) == expected)
    }

    @Test("A leading dot is matched only by a pattern that starts with a dot")
    func leadingDot() {
        #expect(!GlobPattern("*").matches(".config.open-ssh-gui-backup"))
        #expect(!GlobPattern("?config").matches(".config"))
        #expect(!GlobPattern("[.]config").matches(".config"))
        #expect(GlobPattern(".*").matches(".config.open-ssh-gui-backup"))
        #expect(GlobPattern(".config").matches(".config"))
    }

    @Test("Whether a segment is a wildcard decides if a directory has to be listed")
    func hasWildcard() {
        #expect(GlobPattern("*.conf").hasWildcard)
        #expect(GlobPattern("w?rk").hasWildcard)
        #expect(GlobPattern("[ab]").hasWildcard)
        #expect(!GlobPattern("config").hasWildcard)
        #expect(!GlobPattern(#"literal\*"#).hasWildcard)
    }

    @Test("Matches are returned in lexical order, as glob(3) sorts them")
    func lexicalOrder() {
        let names = ["b.conf", "a.conf", "B.conf", "10.conf", "2.conf", ".hidden.conf", "notes.txt"]
        #expect(GlobPattern("*.conf").matches(in: names) == ["10.conf", "2.conf", "B.conf", "a.conf", "b.conf"])
    }

    @Test("A literal segment matches only itself, unescaped")
    func literal() {
        #expect(GlobPattern(#"a\[b"#).literal == "a[b")
        #expect(GlobPattern("plain").literal == "plain")
    }
}
