import Foundation

/// Turns a file's bytes into a lossless `SSHConfigFile`, plus the `Host` entries and `Include`
/// directives it declares.
///
/// Lines are split on the byte `0x0A`, with a preceding `0x0D` recorded as part of the
/// terminator. Never on `Character`: Swift treats `\r\n` as one grapheme, which would hide a
/// CRLF file's endings from everything downstream.
///
/// Pure. It records what each block declares and nothing it would inherit, and it never
/// repairs a line it cannot read.
nonisolated struct SSHConfigParser {

    private let tokenizer = SSHConfigTokenizer()

    init() {}

    func parse(
        _ data: Data,
        at url: URL,
        inclusionChain: [InclusionCondition],
        writability: ConfigWritability
    ) -> ParsedConfigFile {
        let bytes = [UInt8](data)

        // A file that is not UTF-8 is still listed, from a lossy decode, but it is never
        // written: re-encoding it would change bytes the user did not touch.
        let isUTF8 = String(validating: bytes, as: UTF8.self) != nil
        let effectiveWritability = isUTF8 || !writability.isWritable ? writability : .readOnly(.notUTF8)

        let lines = splitLines(bytes)
        let file = SSHConfigFile(
            url: url,
            original: data,
            lines: lines,
            lineTerminator: lines.lazy.compactMap(\.terminator).first ?? .lf,
            inclusionChain: inclusionChain,
            writability: effectiveWritability
        )

        let hostBlocks = file.blocks.filter { $0.kind == .host }

        return ParsedConfigFile(
            file: file,
            entries: hostBlocks.enumerated().compactMap { ordinal, block in
                entry(for: block, ordinal: ordinal, in: file)
            },
            includes: includes(in: lines),
            malformedLines: lines.indices.filter {
                if case .malformed = lines[$0].kind { return true }
                return false
            }
        )
    }

    // MARK: - Lines

    private func splitLines(_ bytes: [UInt8]) -> [SSHConfigLine] {
        var lines: [SSHConfigLine] = []
        var start = 0

        for index in bytes.indices where bytes[index] == 0x0A {
            var textEnd = index
            var terminator = LineTerminator.lf
            if textEnd > start, bytes[textEnd - 1] == 0x0D {
                textEnd -= 1
                terminator = .crlf
            }
            lines.append(line(bytes[start..<textEnd], terminator: terminator))
            start = index + 1
        }

        // A file that ends with a newline has no empty line after it.
        if start < bytes.count {
            lines.append(line(bytes[start...], terminator: nil))
        }

        return lines
    }

    private func line(_ bytes: ArraySlice<UInt8>, terminator: LineTerminator?) -> SSHConfigLine {
        let text = String(decoding: bytes, as: UTF8.self)
        return SSHConfigLine(text: text, terminator: terminator, kind: tokenizer.tokenize(text))
    }

    // MARK: - Entries

    private func entry(for block: ConfigBlock, ordinal: Int, in file: SSHConfigFile) -> HostEntry? {
        guard let header = file.lines[block.headerLine].directive else { return nil }

        var firstValues: [SSHConfigKeyword: DeclaredValue] = [:]
        var identityFiles: [DeclaredValue] = []
        var counts: [SSHConfigKeyword: Int] = [:]

        for index in block.lineRange.dropFirst() {
            guard let directive = file.lines[index].directive, let value = directive.value else { continue }

            counts[directive.keyword, default: 0] += 1
            if directive.keyword == .identityFile {
                identityFiles.append(DeclaredValue(value: value, line: index))
            } else if firstValues[directive.keyword] == nil {
                firstValues[directive.keyword] = DeclaredValue(value: value, line: index)
            }
        }

        return HostEntry(
            id: HostEntryID(file: file.url, ordinal: ordinal),
            lineRange: block.lineRange,
            patterns: header.arguments.map(HostPattern.init(parsing:)),
            hostName: firstValues[.hostName],
            user: firstValues[.user],
            port: firstValues[.port],
            identityFiles: identityFiles,
            repeatedKeywords: Set(counts.filter { $0.value > 1 }.keys),
            writability: file.writability
        )
    }

    // MARK: - Includes

    /// Every `Include`, with the block it sits inside — which decides when its files apply.
    private func includes(in lines: [SSHConfigLine]) -> [IncludeDirective] {
        var condition: InclusionCondition?
        var includes: [IncludeDirective] = []

        for (index, line) in lines.enumerated() {
            guard let directive = line.directive else { continue }

            switch directive.keyword {
            case .host:
                condition = .host(directive.arguments.map(HostPattern.init(parsing:)))
            case .match:
                condition = .match
            case .include:
                includes.append(IncludeDirective(line: index, arguments: directive.arguments, condition: condition))
            default:
                break
            }
        }

        return includes
    }
}
