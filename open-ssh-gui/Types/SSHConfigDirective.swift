import Foundation

/// One `Keyword arguments…` line, read the way OpenSSH reads it.
///
/// The arguments are unescaped — what `ssh` sees — while the spans point into the line's raw
/// text. Both are needed: the arguments decide what a block *means*, and the spans let an edit
/// replace exactly the argument run while the indentation, the keyword's spelling, the
/// separator and any trailing comment survive byte for byte.
///
/// Every span is a range of the line's `text` and is only meaningful against that text.
nonisolated struct SSHConfigDirective: Sendable, Equatable {
    let keyword: SSHConfigKeyword

    /// Unescaped, with quotes removed, as `argv_split` produces them.
    let arguments: [String]

    /// The leading whitespace. Empty for an unindented line.
    let indentation: Range<String.Index>

    let keywordSpan: Range<String.Index>

    /// From the first argument's first character to the last argument's last, which excludes
    /// trailing whitespace and a trailing `# comment`.
    let argumentSpan: Range<String.Index>

    /// The first argument, which is the value for every single-valued keyword this app edits.
    var value: String? { arguments.first }
}
