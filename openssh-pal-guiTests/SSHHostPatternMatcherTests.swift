import Foundation
import Testing

/// Placement and duplicate detection both depend on matching a name against a `Host` line
/// exactly as `ssh` does: lowercase the name, glob `*` and `?`, and let any matching negation
/// veto the whole line.
@Suite("Host pattern matcher")
nonisolated struct SSHHostPatternMatcherTests {

    private static func matches(_ candidate: String, _ patterns: String...) -> Bool {
        SSHHostPatternMatcher().matches(candidate, patterns: patterns.map(HostPattern.init(parsing:)))
    }

    @Test("A literal pattern matches the same name, whatever case the name is typed in")
    func literal() {
        #expect(Self.matches("github.com", "github.com"))
        #expect(Self.matches("GitHub.COM", "github.com"))
        #expect(!Self.matches("gitlab.com", "github.com"))
    }

    @Test("* and ? glob, and nothing else does")
    func wildcards() {
        #expect(Self.matches("anything", "*"))
        #expect(Self.matches("db.corp", "*.corp"))
        #expect(!Self.matches("corp", "*.corp"))
        #expect(Self.matches("db1", "db?"))
        #expect(!Self.matches("db12", "db?"))
        #expect(!Self.matches("a", "[a]"))
    }

    @Test("Any matching negated pattern vetoes the line, even when a positive one matches")
    func negationVetoes() {
        #expect(!Self.matches("db.corp", "*.corp", "!db.corp"))
        #expect(Self.matches("web.corp", "*.corp", "!db.corp"))
        #expect(!Self.matches("db.corp", "!db.corp", "*.corp"))
    }

    @Test("A line with no positive match does not match, even if every negation misses")
    func noPositiveMatch() {
        #expect(!Self.matches("web", "!db"))
        #expect(!Self.matches("web"))
    }

    @Test("A pattern containing upper-case letters never matches, because ssh lowercases the host")
    func upperCasePatternsNeverMatch() {
        #expect(!Self.matches("github.com", "GitHub.com"))
        #expect(!Self.matches("GitHub.com", "GitHub.com"))
    }
}
