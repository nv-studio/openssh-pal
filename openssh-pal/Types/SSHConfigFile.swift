import Foundation

/// One configuration file, held losslessly.
///
/// Every rule reads this and every edit is applied to it. The app never serialises a file from
/// a model: a write is these lines with specific ranges replaced, inserted or removed, so there
/// is no "render the file" function to get wrong.
nonisolated struct SSHConfigFile: Sendable, Equatable {
    let url: URL

    /// The bytes as read, which is also the baseline a write is compared against.
    let original: Data

    let lines: [SSHConfigLine]

    /// The terminator of the first terminated line, or LF for a file with none. New lines end
    /// with it.
    let lineTerminator: LineTerminator

    /// The `Include` conditions this file was reached through. Empty for `config` itself and
    /// for anything included from a global section.
    let inclusionChain: [InclusionCondition]

    let writability: ConfigWritability

    /// Whether the last line ends with a newline. An empty file counts as ending with one, so
    /// a block added to it ends the way a new file would.
    var endsWithNewline: Bool {
        lines.last.map { $0.terminator != nil } ?? true
    }

    /// The `Host` and `Match` blocks, in file order.
    var blocks: [ConfigBlock] {
        let headers: [(Int, ConfigBlock.Kind)] = lines.indices.compactMap { index in
            switch lines[index].directive?.keyword {
            case .host?: (index, .host)
            case .match?: (index, .match)
            default: nil
            }
        }

        return headers.indices.map { position in
            let (start, kind) = headers[position]
            let end = position + 1 < headers.count ? headers[position + 1].0 : lines.count
            return ConfigBlock(kind: kind, lineRange: start..<end)
        }
    }

    /// Where the comments attached to the block whose header is at `headerLine` begin.
    ///
    /// Attached means contiguous, unindented comment lines directly above the header with no
    /// blank line between: `# work machines` immediately above `Host *.corp` belongs to it,
    /// and moves or goes with it. Returns `headerLine` itself when nothing is attached.
    func attachedCommentStart(before headerLine: Int) -> Int {
        var start = headerLine
        while start > 0, lines[start - 1].isComment, !lines[start - 1].isIndented {
            start -= 1
        }
        return start
    }

    /// The last line of `range` that says something — a directive or a malformed line — or
    /// the range's first line when nothing does. Blank lines and comments after it trail the
    /// block rather than belong to its directives.
    func lastContentLine(in range: Range<Int>) -> Int {
        range.reversed().first { !lines[$0].isBlank && !lines[$0].isComment } ?? range.lowerBound
    }

    /// The indentation of the first indented directive in `range`, if any.
    func directiveIndentation(in range: Range<Int>) -> String? {
        for index in range {
            let line = lines[index]
            guard let directive = line.directive, !directive.indentation.isEmpty else { continue }
            return line.text(in: directive.indentation)
        }
        return nil
    }

    /// The same file with a different writability.
    func withWritability(_ writability: ConfigWritability) -> SSHConfigFile {
        SSHConfigFile(
            url: url,
            original: original,
            lines: lines,
            lineTerminator: lineTerminator,
            inclusionChain: inclusionChain,
            writability: writability
        )
    }
}
