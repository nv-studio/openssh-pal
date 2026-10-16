import Foundation

/// Decides where in `config` a new block goes, and what will still take precedence over it.
///
/// `ssh` assigns each parameter the first value it obtains, so a block that matches the new
/// alias and comes earlier would silently pre-empt the new block's values. The new block
/// therefore goes immediately before the first `Host` block in `config` that matches the alias
/// — before that block's attached comments — and is appended otherwise.
///
/// It never goes above the first `Host` or `Match` line, so global directives and `Include`
/// lines keep applying to every host. `Match` blocks are disregarded: their criteria cannot be
/// evaluated without a connection.
///
/// A matching block the new one cannot be placed above — in a file included earlier — is
/// reported rather than worked around, so the user can decide.
///
/// Pure.
nonisolated struct HostBlockPlacement {

    private let matcher = SSHHostPatternMatcher()

    init() {}

    func place(alias: String, in configuration: SSHConfiguration) -> PlacementDecision {
        guard let root = configuration.root else {
            return PlacementDecision(point: .end, precedingMatches: [])
        }

        let firstMatch = configuration.entries.first {
            $0.file == root.url && matcher.matches(alias, patterns: $0.patterns)
        }

        let point: InsertionPoint
        if let firstMatch {
            let firstHeader = root.blocks.first?.headerLine ?? firstMatch.headerLine
            point = .before(line: max(root.attachedCommentStart(before: firstMatch.headerLine), firstHeader))
        } else {
            point = .end
        }

        return PlacementDecision(
            point: point,
            precedingMatches: precedingMatches(of: alias, before: firstMatch, in: configuration, root: root)
        )
    }

    /// Matching blocks from included files that `ssh` reads before the insertion point.
    ///
    /// The flattened load order already interleaves included files at their `Include` lines,
    /// so "before the insertion point" is "before the block the new one goes above".
    private func precedingMatches(
        of alias: String,
        before boundary: HostEntry?,
        in configuration: SSHConfiguration,
        root: SSHConfigFile
    ) -> [PrecedingMatch] {
        var matches: [PrecedingMatch] = []

        for entry in configuration.entries {
            if entry.id == boundary?.id { break }
            guard entry.file != root.url, matcher.matches(alias, patterns: entry.patterns) else { continue }

            // An included file applies only when every block it was included under does.
            var isConditional = false
            var applies = true
            for condition in configuration.file(at: entry.file)?.inclusionChain ?? [] {
                switch condition {
                case .host(let patterns):
                    applies = applies && matcher.matches(alias, patterns: patterns)
                case .match:
                    isConditional = true
                }
            }
            guard applies else { continue }

            matches.append(
                PrecedingMatch(entry: entry.id, displayName: entry.displayName, file: entry.file, isConditional: isConditional)
            )
        }

        return matches
    }
}
