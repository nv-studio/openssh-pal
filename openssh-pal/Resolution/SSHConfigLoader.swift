import Foundation

/// Reads `config` and every file it reaches through `Include`, the way `ssh` does.
///
/// Lives in `Resolution/` as `SSHDirectoryResolver` does: it depends on the read port, never on
/// an adapter. Every read goes through the port, whose adapter is `@concurrent`, so a load never
/// runs file I/O on the main actor.
///
/// Includes are walked depth-first at the position each directive appears, so entries come out
/// in the order `ssh` reads them. Nothing stops a load except `config` itself being missing or
/// unreadable: every other problem becomes an issue, and everything readable is kept.
nonisolated struct SSHConfigLoader {

    /// OpenSSH's `READCONF_MAX_DEPTH`. `config` is depth zero, so a file at depth 17 is not read.
    static let maximumDepth = 16

    /// The file OpenSSH reads in the SSH directory.
    static let configFileName = "config"

    private let reader: SSHDirectoryReading
    private let parser: SSHConfigParser
    private let expander = IncludePathExpander()

    init(reader: SSHDirectoryReading, parser: SSHConfigParser) {
        self.reader = reader
        self.parser = parser
    }

    func load(in directory: SSHDirectory, context: IdentityResolutionContext) async -> ConfigLoadOutcome {
        let config = directory.url.appending(path: Self.configFileName)

        let data: Data
        do {
            data = try await reader.contents(of: config)
        } catch .directoryNotFound {
            return .noConfigFile
        } catch {
            return .unreadable(error)
        }

        var walk = Walk()
        await visit(
            data,
            at: config,
            chain: [],
            depth: 0,
            ancestors: [IdentityResolutionContext.normalizedPath(of: config)],
            context: context,
            into: &walk
        )

        return .loaded(
            SSHConfiguration(files: walk.files, entries: walk.entries, issues: walk.issues, includePatterns: walk.patterns)
        )
    }

    /// What a load has gathered so far.
    private struct Walk {
        var files: [SSHConfigFile] = []
        var entries: [HostEntry] = []
        var issues: [ConfigLoadIssue] = []
        var patterns: [GlobPath] = []
    }

    // MARK: - Files

    private func visit(
        _ data: Data,
        at url: URL,
        chain: [InclusionCondition],
        depth: Int,
        ancestors: [String],
        context: IdentityResolutionContext,
        into walk: inout Walk
    ) async {
        let writability: ConfigWritability = context.contains(url) ? .writable : .readOnly(.outsideDirectory)
        let parsed = parser.parse(data, at: url, inclusionChain: chain, writability: writability)

        walk.files.append(parsed.file)
        for line in parsed.malformedLines {
            if case .malformed(let reason) = parsed.file.lines[line].kind {
                walk.issues.append(.unparseableLine(file: url, line: line, reason: reason))
            }
        }

        // Entries and includes interleaved by line: an included file's hosts come exactly where
        // its `Include` is, which is what `ssh`'s first-obtained-value-wins depends on.
        var pending = parsed.includes[...]
        for entry in parsed.entries {
            while let include = pending.first, include.line < entry.headerLine {
                pending.removeFirst()
                await follow(include, from: url, chain: chain, depth: depth, ancestors: ancestors, context: context, into: &walk)
            }
            walk.entries.append(entry)
        }
        for include in pending {
            await follow(include, from: url, chain: chain, depth: depth, ancestors: ancestors, context: context, into: &walk)
        }
    }

    // MARK: - Includes

    private func follow(
        _ include: IncludeDirective,
        from url: URL,
        chain: [InclusionCondition],
        depth: Int,
        ancestors: [String],
        context: IdentityResolutionContext,
        into walk: inout Walk
    ) async {
        let childChain = chain + (include.condition.map { [$0] } ?? [])

        for argument in include.arguments {
            let glob: GlobPath
            switch expander.expand(argument, in: context) {
            case .success(let expanded):
                glob = expanded
            case .failure(let reason):
                walk.issues.append(.skippedInclude(file: url, line: include.line, argument: argument, reason: reason))
                continue
            }

            walk.patterns.append(glob)

            for match in await matches(of: glob) {
                let path = IdentityResolutionContext.normalizedPath(of: match)

                // OpenSSH has no cycle detection of its own and only stops at the depth limit;
                // catching the cycle names the file that causes it, which the limit does not.
                if ancestors.contains(path) {
                    walk.issues.append(.includeCycle(file: match))
                    continue
                }
                guard depth + 1 <= Self.maximumDepth else {
                    walk.issues.append(.includeDepthExceeded(file: match))
                    continue
                }

                let data: Data
                do {
                    data = try await reader.contents(of: match)
                } catch .directoryNotFound {
                    // `ssh` skips a file that is not there without complaint.
                    continue
                } catch {
                    walk.issues.append(.unreadable(file: match, error))
                    continue
                }

                await visit(
                    data,
                    at: match,
                    chain: childChain,
                    depth: depth + 1,
                    ancestors: ancestors + [path],
                    context: context,
                    into: &walk
                )
            }
        }
    }

    /// The files a glob path names, walked one directory level at a time.
    ///
    /// A literal segment is appended without a read; only a wildcard segment lists its parent.
    /// A directory that cannot be listed contributes nothing, as glob(3) without `GLOB_ERR`
    /// behaves. A wholly literal path is returned as is, and reading it decides whether it is
    /// there.
    private func matches(of glob: GlobPath) async -> [URL] {
        var candidates = [URL(filePath: "/", directoryHint: .isDirectory)]
        var hasWildcard = false

        for (index, segment) in glob.segments.enumerated() {
            let pattern = GlobPattern(segment)
            let isLast = index == glob.segments.count - 1

            guard pattern.hasWildcard else {
                candidates = candidates.map {
                    $0.appending(path: pattern.literal, directoryHint: isLast ? .notDirectory : .isDirectory)
                }
                continue
            }

            hasWildcard = true
            var next: [URL] = []
            for directory in candidates {
                guard let entries = try? await reader.entries(in: directory) else { continue }

                // The last segment names files; any earlier one names directories.
                let eligible = entries.filter { $0.hasDirectoryPath != isLast }
                let byName = Dictionary(eligible.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
                next += pattern.matches(in: Array(byName.keys)).compactMap { byName[$0] }
            }
            candidates = next
        }

        guard hasWildcard else { return candidates }
        return candidates.sorted {
            $0.path(percentEncoded: false).utf8.lexicographicallyPrecedes($1.path(percentEncoded: false).utf8)
        }
    }
}
