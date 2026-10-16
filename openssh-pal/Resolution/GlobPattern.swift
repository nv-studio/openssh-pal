import Foundation

/// One path segment of a glob(3) pattern: `*`, `?`, `[…]` and backslash escapes.
///
/// Matches one directory level only, because glob never lets a wildcard cross a `/`. The
/// leading-dot rule is the part that matters most here: a name starting with `.` is matched
/// only by a pattern that starts with a literal `.`, which is what keeps `Include config.d/*`
/// from reading the app's own hidden backup and temporary files.
///
/// Pure.
nonisolated struct GlobPattern {

    let pattern: String

    private let scalars: [Unicode.Scalar]

    init(_ pattern: String) {
        self.pattern = pattern
        scalars = Array(pattern.unicodeScalars)
    }

    /// Whether the segment can match more than one name, so a directory has to be listed.
    var hasWildcard: Bool {
        var index = 0
        while index < scalars.count {
            switch scalars[index] {
            case "\\": index += 2
            case "*", "?", "[": return true
            default: index += 1
            }
        }
        return false
    }

    /// The segment with escapes removed, for a segment with no wildcard.
    var literal: String {
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            if scalars[index] == "\\", index + 1 < scalars.count { index += 1 }
            result.append(scalars[index])
            index += 1
        }
        return String(result)
    }

    func matches(_ name: String) -> Bool {
        let name = Array(name.unicodeScalars)

        if name.first == ".", !startsWithLiteralDot { return false }
        return Self.match(scalars, name)
    }

    /// The names this segment matches, in the byte order glob(3) sorts them in.
    func matches(in names: [String]) -> [String] {
        names
            .filter(matches)
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    private var startsWithLiteralDot: Bool {
        scalars.first == "." || (scalars.count > 1 && scalars[0] == "\\" && scalars[1] == ".")
    }

    // MARK: - Matching

    /// Iterative matching with single-star backtracking, which is linear for the patterns a
    /// configuration contains and cannot recurse without bound.
    private static func match(_ pattern: [Unicode.Scalar], _ name: [Unicode.Scalar]) -> Bool {
        var p = 0
        var n = 0
        var star: (pattern: Int, name: Int)?

        while n < name.count {
            if p < pattern.count, let advance = step(pattern, at: p, against: name[n]) {
                if advance == 0 {
                    // A star: remember where to resume, and first try matching nothing.
                    star = (p, n)
                    p += 1
                } else {
                    p += advance
                    n += 1
                }
                continue
            }
            guard let resume = star else { return false }
            star = (resume.pattern, resume.name + 1)
            p = resume.pattern + 1
            n = resume.name + 1
        }

        while p < pattern.count, pattern[p] == "*" { p += 1 }
        return p == pattern.count
    }

    /// How far the pattern advances when `scalar` is consumed at `index`: `0` for a star,
    /// `nil` when it does not match.
    private static func step(_ pattern: [Unicode.Scalar], at index: Int, against scalar: Unicode.Scalar) -> Int? {
        switch pattern[index] {
        case "*":
            return 0
        case "?":
            return 1
        case "[":
            guard let (matched, length) = characterClass(pattern, at: index, against: scalar) else {
                // No closing bracket: the `[` is an ordinary character.
                return scalar == "[" ? 1 : nil
            }
            return matched ? length : nil
        case "\\" where index + 1 < pattern.count:
            return pattern[index + 1] == scalar ? 2 : nil
        default:
            return pattern[index] == scalar ? 1 : nil
        }
    }

    /// Whether a `[…]` class at `index` contains `scalar`, and how long the class is. `nil`
    /// when the bracket is never closed.
    private static func characterClass(
        _ pattern: [Unicode.Scalar],
        at index: Int,
        against scalar: Unicode.Scalar
    ) -> (Bool, Int)? {
        var cursor = index + 1
        var negated = false
        if cursor < pattern.count, pattern[cursor] == "!" || pattern[cursor] == "^" {
            negated = true
            cursor += 1
        }

        var matched = false
        var first = true

        while cursor < pattern.count {
            // A `]` straight after the opening bracket is a member, not the end.
            if pattern[cursor] == "]", !first {
                return (matched != negated, cursor + 1 - index)
            }
            first = false

            let low = pattern[cursor]
            if cursor + 2 < pattern.count, pattern[cursor + 1] == "-", pattern[cursor + 2] != "]" {
                let high = pattern[cursor + 2]
                if low.value <= scalar.value, scalar.value <= high.value { matched = true }
                cursor += 3
            } else {
                if low == scalar { matched = true }
                cursor += 1
            }
        }

        return nil
    }
}
