import Foundation

/// One line of a configuration file: its raw text, how it ended, and what it says.
///
/// The text excludes the terminator and the terminator is kept beside it, so concatenating
/// `text` and `terminator` over every line reproduces the file. That is the round-trip
/// invariant every preservation guarantee in this feature rests on.
nonisolated struct SSHConfigLine: Sendable, Equatable {
    let text: String

    /// `nil` only for a last line with no newline after it.
    let terminator: LineTerminator?

    let kind: Kind

    nonisolated enum Kind: Sendable, Equatable {
        /// Empty or whitespace only.
        case blank

        /// A line whose first token starts with `#`.
        case comment

        case directive(SSHConfigDirective)

        /// A line OpenSSH would reject. Kept, never repaired.
        case malformed(MalformedReason)
    }

    /// Why a line could not be read.
    nonisolated enum MalformedReason: Sendable, Equatable {
        /// A quote opened and never closed — OpenSSH's "invalid quotes".
        case invalidQuotes

        /// A keyword with nothing after it.
        case missingArgument

        /// A line that starts with a separator or a quote instead of a keyword.
        case missingKeyword

        var description: String {
            switch self {
            case .invalidQuotes: "a quote is not closed"
            case .missingArgument: "the keyword has no value"
            case .missingKeyword: "the line does not start with a keyword"
            }
        }
    }

    var directive: SSHConfigDirective? {
        guard case .directive(let directive) = kind else { return nil }
        return directive
    }

    var isBlank: Bool { kind == .blank }

    var isComment: Bool { kind == .comment }

    /// Whether the line starts with whitespace, which decides whether a comment above a `Host`
    /// line belongs to that block or to the one before it.
    var isIndented: Bool {
        text.unicodeScalars.first.map { $0 == " " || $0 == "\t" } ?? false
    }

    /// The text a span covers. Spans are scalar-aligned, so this slices scalars rather than
    /// characters: a combining mark after a separator must not drag the separator into it.
    func text(in span: Range<String.Index>) -> String {
        String(text.unicodeScalars[span])
    }

    /// The bytes this line occupies in its file, terminator included.
    var bytes: [UInt8] {
        Array(text.utf8) + (terminator?.bytes ?? [])
    }
}
