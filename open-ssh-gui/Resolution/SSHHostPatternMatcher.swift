import Foundation

/// Matches a host name against a `Host` line's patterns with OpenSSH's semantics.
///
/// `ssh` lowercases the host before calling `match_pattern`, which is a case-*sensitive* glob
/// over `*` and `?` only. Two consequences are reproduced deliberately: the candidate is
/// lowercased here, and a pattern containing an upper-case letter therefore never matches.
///
/// A negated pattern that matches vetoes the whole line, whatever else matches.
///
/// Pure.
nonisolated struct SSHHostPatternMatcher {

    init() {}

    func matches(_ candidate: String, patterns: [HostPattern]) -> Bool {
        let name = Array(candidate.lowercased().unicodeScalars)
        var matched = false

        for pattern in patterns where Self.match(Array(pattern.text.unicodeScalars), name) {
            if pattern.isNegated { return false }
            matched = true
        }
        return matched
    }

    /// `match_pattern`: `*` matches any run, `?` any one character, everything else itself.
    private static func match(_ pattern: [Unicode.Scalar], _ name: [Unicode.Scalar]) -> Bool {
        var p = 0
        var n = 0
        var star: (pattern: Int, name: Int)?

        while n < name.count {
            if p < pattern.count, pattern[p] == "*" {
                star = (p, n)
                p += 1
            } else if p < pattern.count, pattern[p] == "?" || pattern[p] == name[n] {
                p += 1
                n += 1
            } else if let resume = star {
                star = (resume.pattern, resume.name + 1)
                p = resume.pattern + 1
                n = resume.name + 1
            } else {
                return false
            }
        }

        while p < pattern.count, pattern[p] == "*" { p += 1 }
        return p == pattern.count
    }
}
