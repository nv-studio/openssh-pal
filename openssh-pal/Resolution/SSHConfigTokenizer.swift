import Foundation

/// Reads one configuration line exactly as OpenSSH does.
///
/// A port of `process_config_line` (keyword and separator) and
/// `argv_split(…, terminate_on_comment = 1)` (arguments) from `readconf.c` and `misc.c`. It is
/// separate from the parser because quoting is where a misread would rewrite the wrong text:
/// every span this returns is what an edit will replace.
///
/// Works on Unicode scalars rather than `Character`s. Every delimiter OpenSSH recognises is
/// ASCII, and grapheme clustering would let a combining mark after a space swallow the space.
///
/// Pure, and never fails: a line it cannot read is `.malformed`, and the caller keeps its raw
/// text.
nonisolated struct SSHConfigTokenizer {

    init() {}

    func tokenize(_ line: String) -> SSHConfigLine.Kind {
        let scalars = Array(line.unicodeScalars)
        let indices = Array(line.unicodeScalars.indices) + [line.endIndex]

        // `process_config_line` strips trailing whitespace and a form feed before anything else.
        var end = scalars.count
        while end > 0, Self.isTrailingWhitespace(scalars[end - 1]) { end -= 1 }

        var cursor = 0
        while cursor < end, Self.isWhitespace(scalars[cursor]) { cursor += 1 }
        let indentationEnd = cursor

        guard cursor < end else { return .blank }
        guard scalars[cursor] != "#" else { return .comment }

        // The keyword ends at whitespace, at `=` or at a quote — `strdelim`'s delimiters.
        let keywordStart = cursor
        while cursor < end, !Self.endsKeyword(scalars[cursor]) { cursor += 1 }
        let keywordEnd = cursor

        guard keywordStart < keywordEnd else { return .malformed(.missingKeyword) }

        cursor = Self.skipSeparator(in: scalars, from: cursor, to: end)

        guard let arguments = Self.splitArguments(scalars, from: cursor, to: end) else {
            return .malformed(.invalidQuotes)
        }
        guard let first = arguments.first, let last = arguments.last else {
            return .malformed(.missingArgument)
        }

        return .directive(
            SSHConfigDirective(
                keyword: SSHConfigKeyword(String(String.UnicodeScalarView(scalars[keywordStart..<keywordEnd]))),
                arguments: arguments.map(\.value),
                indentation: indices[0]..<indices[indentationEnd],
                keywordSpan: indices[keywordStart]..<indices[keywordEnd],
                argumentSpan: indices[first.range.lowerBound]..<indices[last.range.upperBound]
            )
        )
    }

    // MARK: - Separator

    /// Skips whitespace, or optional whitespace plus exactly one `=` plus whitespace.
    ///
    /// Mirrors `strdelim`: a keyword ended by `=` consumes that `=` and the whitespace after
    /// it, and nothing more; a keyword ended by whitespace may still be followed by one `=`.
    private static func skipSeparator(in scalars: [Unicode.Scalar], from start: Int, to end: Int) -> Int {
        var cursor = start
        guard cursor < end else { return cursor }

        if scalars[cursor] == "=" {
            cursor += 1
            while cursor < end, isWhitespace(scalars[cursor]) { cursor += 1 }
            return cursor
        }

        guard isWhitespace(scalars[cursor]) else { return cursor }
        while cursor < end, isWhitespace(scalars[cursor]) { cursor += 1 }

        if cursor < end, scalars[cursor] == "=" {
            cursor += 1
            while cursor < end, isWhitespace(scalars[cursor]) { cursor += 1 }
        }
        return cursor
    }

    // MARK: - Arguments

    private struct Token {
        let value: String
        let range: Range<Int>
    }

    /// `argv_split` with comment termination. `nil` for an unterminated quote.
    private static func splitArguments(_ scalars: [Unicode.Scalar], from start: Int, to end: Int) -> [Token]? {
        var tokens: [Token] = []
        var cursor = start

        while cursor < end {
            let scalar = scalars[cursor]

            if scalar == " " || scalar == "\t" {
                cursor += 1
                continue
            }
            // Only a token that *starts* with `#` ends the line; `a#b` is one argument.
            if scalar == "#" { break }

            let tokenStart = cursor
            var value = String.UnicodeScalarView()
            var quote: Unicode.Scalar?

            while cursor < end {
                let current = scalars[cursor]

                if current == "\\" {
                    let next = cursor + 1 < end ? scalars[cursor + 1] : nil
                    if let next, next == "'" || next == "\"" || next == "\\" || (quote == nil && next == " ") {
                        cursor += 1
                        value.append(next)
                    } else {
                        // An unrecognised escape is kept, backslash and all.
                        value.append(current)
                    }
                } else if quote == nil, current == " " || current == "\t" {
                    break
                } else if quote == nil, current == "\"" || current == "'" {
                    quote = current
                } else if let open = quote, current == open {
                    quote = nil
                } else {
                    value.append(current)
                }
                cursor += 1
            }

            guard quote == nil else { return nil }
            tokens.append(Token(value: String(value), range: tokenStart..<cursor))
        }

        return tokens
    }

    // MARK: - Character classes

    /// `WHITESPACE` in `readconf.c`, which the keyword and separator are read with.
    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\r" || scalar == "\n"
    }

    private static func isTrailingWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        isWhitespace(scalar) || scalar == "\u{0C}"
    }

    private static func endsKeyword(_ scalar: Unicode.Scalar) -> Bool {
        isWhitespace(scalar) || scalar == "=" || scalar == "\""
    }
}
