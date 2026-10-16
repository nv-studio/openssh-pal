import Foundation

/// Produces a file's new bytes from its lossless lines and one change to one block.
///
/// Every operation is expressed as line replacements, removals and insertions against the
/// original, and every line it does not name is copied from the original **as bytes**. There is
/// no "render the whole file" step, so nothing outside the change can be reformatted.
///
/// New lines end with the file's dominant terminator, and the file's final-newline state is
/// kept: a file that did not end with a newline still does not.
///
/// Pure.
nonisolated struct HostBlockEditor {

    /// The indentation a new directive gets when neither its block nor its file has one.
    static let defaultIndentation = "    "

    private let formatter = SSHConfigValueFormatter()

    init() {}

    // MARK: - Edit

    /// Applies a draft to the block `entry` describes in `file`.
    ///
    /// Only what changed is touched: a changed value rewrites its argument span, a cleared one
    /// removes its line, a new one is inserted after the block's last directive. The `Host` line
    /// is rewritten only when the patterns change, and `IdentityFile` lines only when the key
    /// choice says so.
    func applying(
        _ draft: ValidatedHostDraft,
        to entry: HostEntry,
        in file: SSHConfigFile,
        context: IdentityResolutionContext
    ) -> Data {
        var change = Change()
        let indentation = indentation(for: entry.lineRange, in: file)
        var added: [String] = []

        if draft.patterns != entry.patterns.map(\.token) {
            change.replace(entry.headerLine, in: file, argument: patternsArgument(draft.patterns))
        }

        let fields: [(String, DeclaredValue?, String?)] = [
            ("HostName", entry.hostName, draft.hostName),
            ("User", entry.user, draft.user),
            ("Port", entry.port, draft.port),
        ]
        for (keyword, current, value) in fields {
            switch (current, value) {
            case (nil, nil):
                break
            case (let current?, nil):
                change.removals.insert(current.line)
            case (nil, let value?):
                added.append(indentation + keyword + " " + formatter.argument(for: value))
            case (let current?, let value?):
                if current.value != value {
                    change.replace(current.line, in: file, argument: formatter.argument(for: value))
                }
            }
        }

        switch draft.keyChoice {
        case .unchanged:
            break
        case .none:
            change.removals.formUnion(entry.identityFiles.map(\.line))
        case .pair(let name):
            let argument = formatter.identityFileArgument(for: name, context: context)
            if let first = entry.identityFiles.first {
                if file.lines[first.line].directive.map({ file.lines[first.line].text(in: $0.argumentSpan) }) != argument {
                    change.replace(first.line, in: file, argument: argument)
                }
                change.removals.formUnion(entry.identityFiles.dropFirst().map(\.line))
            } else {
                added.append(indentation + "IdentityFile " + argument)
            }
        }

        if !added.isEmpty {
            change.insertions[file.lastContentLine(in: entry.lineRange) + 1, default: []] += added
        }

        return render(file, change)
    }

    // MARK: - Insert

    /// Adds a new block at `point`, separated from each neighbour by exactly one blank line.
    func inserting(
        _ draft: ValidatedHostDraft,
        at point: InsertionPoint,
        in file: SSHConfigFile,
        context: IdentityResolutionContext
    ) -> Data {
        var block = blockLines(for: draft, indentation: fileIndentation(file), context: context)
        var change = Change()

        switch point {
        case .end:
            // An existing trailing blank already separates; a file of nothing but blank lines
            // has no neighbour to separate from.
            let hasContent = file.lines.contains { !$0.isBlank }
            if hasContent, file.lines.last?.isBlank == false {
                block.insert("", at: 0)
            }
            change.insertions[file.lines.count] = block
        case .before(let line):
            if line > 0, !file.lines[line - 1].isBlank {
                block.insert("", at: 0)
            }
            change.insertions[line] = block + [""]
        }

        return render(file, change)
    }

    /// The contents of a brand-new configuration file holding only the new block.
    func newFile(containing draft: ValidatedHostDraft, context: IdentityResolutionContext) -> Data {
        let lines = blockLines(for: draft, indentation: Self.defaultIndentation, context: context)
        return Data(lines.flatMap { Array($0.utf8) + LineTerminator.lf.bytes })
    }

    // MARK: - Remove

    /// Removes the block, the comments attached above it and one adjacent blank line.
    ///
    /// The block's own range runs to the next header, which would include the comments attached
    /// to *that* block; those stay. So do blank lines trailing the block, except the one that
    /// would otherwise leave a double blank — or a blank at either end of the file.
    func removing(_ entry: HostEntry, from file: SSHConfigFile) -> Data {
        let start = file.attachedCommentStart(before: entry.headerLine)

        var end = entry.lineRange.upperBound
        if end < file.lines.count {
            end = max(entry.headerLine + 1, file.attachedCommentStart(before: end))
        }
        while end > entry.headerLine + 1, file.lines[end - 1].isBlank { end -= 1 }

        var change = Change()
        change.removals = Set(start..<end)

        let blankBefore = start > 0 && file.lines[start - 1].isBlank
        let blankAfter = end < file.lines.count && file.lines[end].isBlank
        if blankAfter, blankBefore || start == 0 {
            change.removals.insert(end)
        } else if blankBefore, end == file.lines.count {
            change.removals.insert(start - 1)
        }

        return render(file, change)
    }

    // MARK: - Building lines

    private func blockLines(for draft: ValidatedHostDraft, indentation: String, context: IdentityResolutionContext) -> [String] {
        var lines = ["Host " + patternsArgument(draft.patterns)]
        if let hostName = draft.hostName { lines.append(indentation + "HostName " + formatter.argument(for: hostName)) }
        if let user = draft.user { lines.append(indentation + "User " + formatter.argument(for: user)) }
        if let port = draft.port { lines.append(indentation + "Port " + formatter.argument(for: port)) }
        if case .pair(let name) = draft.keyChoice {
            lines.append(indentation + "IdentityFile " + formatter.identityFileArgument(for: name, context: context))
        }
        return lines
    }

    private func patternsArgument(_ patterns: [String]) -> String {
        patterns.map(formatter.argument(for:)).joined(separator: " ")
    }

    /// The block's own indentation, then the file's, then four spaces.
    private func indentation(for range: Range<Int>, in file: SSHConfigFile) -> String {
        file.directiveIndentation(in: range.dropFirst().startIndex..<range.upperBound) ?? fileIndentation(file)
    }

    private func fileIndentation(_ file: SSHConfigFile) -> String {
        file.directiveIndentation(in: file.lines.indices) ?? Self.defaultIndentation
    }

    // MARK: - Rendering

    /// What to do to the original lines.
    private struct Change {
        var replacements: [Int: String] = [:]
        var removals: Set<Int> = []

        /// New lines to place immediately before the given index; the line count means the end.
        var insertions: [Int: [String]] = [:]

        /// Replaces only the argument span of `index`, keeping everything around it.
        mutating func replace(_ index: Int, in file: SSHConfigFile, argument: String) {
            let line = file.lines[index]
            guard let directive = line.directive else { return }
            let scalars = line.text.unicodeScalars
            replacements[index] = String(scalars[..<directive.argumentSpan.lowerBound])
                + argument
                + String(scalars[directive.argumentSpan.upperBound...])
        }
    }

    private func render(_ file: SSHConfigFile, _ change: Change) -> Data {
        var lines: [(text: [UInt8], terminator: LineTerminator)] = []

        for index in 0...file.lines.count {
            for added in change.insertions[index] ?? [] {
                lines.append((Array(added.utf8), file.lineTerminator))
            }
            guard index < file.lines.count, !change.removals.contains(index) else { continue }

            let original = file.lines[index]
            let text = change.replacements[index].map { Array($0.utf8) } ?? Array(original.text.utf8)
            // An unterminated last line that is no longer last needs a terminator; which one
            // the file mostly uses is the only choice that does not stand out.
            lines.append((text, original.terminator ?? file.lineTerminator))
        }

        var bytes: [UInt8] = []
        for (position, line) in lines.enumerated() {
            bytes += line.text
            let isLast = position == lines.count - 1
            if !isLast || file.endsWithNewline {
                bytes += line.terminator.bytes
            }
        }
        return Data(bytes)
    }
}
