import Foundation
import Testing

/// `ssh` takes the first value it obtains for each parameter, so where a new block goes decides
/// whether its values apply at all. The block goes before the first `Host` block in `config`
/// that would pre-empt it, and anything that still precedes it is reported.
@Suite("Host block placement")
nonisolated struct HostBlockPlacementTests {

    private static let home = URL(filePath: "/fabricated/home", directoryHint: .isDirectory)
    private static let keys = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)

    /// Loads `files` (relative to the override directory) through the real loader, so include
    /// chains are exactly what loading produces.
    private static func configuration(_ files: [String: String], directories: [URL: [URL]] = [:]) async throws -> SSHConfiguration {
        let reader = InMemorySSHDirectoryReader(
            directories: directories.merging([keys: []]) { existing, _ in existing },
            files: Dictionary(uniqueKeysWithValues: files.map { (keys.appending(path: $0.key), Data($0.value.utf8)) })
        )
        let context = IdentityResolutionContext(
            homeDirectory: home,
            sshDirectory: SSHDirectory(url: keys),
            userName: "alice",
            defaultDirectory: home.appending(path: SSHDirectoryResolver.directoryName)
        )
        guard case .loaded(let configuration) = await SSHConfigLoader(reader: reader, parser: SSHConfigParser())
            .load(in: SSHDirectory(url: keys), context: context)
        else {
            Issue.record("the configuration did not load")
            throw CancellationError()
        }
        return configuration
    }

    private static func place(_ alias: String, _ configuration: SSHConfiguration) -> PlacementDecision {
        HostBlockPlacement().place(alias: alias, in: configuration)
    }

    // MARK: - 6.6 / 6.7

    @Test("Host * first: the new block goes above it, so its values are not pre-empted")
    func wildcardFirst() async throws {
        let configuration = try await Self.configuration(["config": "Host *\n    User everyone\n\nHost other\n"])
        #expect(Self.place("new", configuration) == PlacementDecision(point: .before(line: 0), precedingMatches: []))
    }

    @Test("Host * last: the new block goes just above it, together with its attached comments")
    func wildcardLast() async throws {
        let configuration = try await Self.configuration(["config": "Host a\n\n# defaults\nHost *\n    User everyone\n"])
        #expect(Self.place("new", configuration).point == .before(line: 2))
    }

    @Test("A wildcard domain block is matched as ssh would, and a non-matching alias is appended")
    func wildcardDomain() async throws {
        let configuration = try await Self.configuration(["config": "Host web\n\nHost *.corp\n    User c\n"])
        #expect(Self.place("db.corp", configuration).point == .before(line: 2))
        #expect(Self.place("DB.CORP", configuration).point == .before(line: 2))
        #expect(Self.place("db.lan", configuration).point == .end)
    }

    @Test("A negated pattern keeps its block from matching")
    func negatedPattern() async throws {
        let configuration = try await Self.configuration(["config": "Host *.corp !db.corp\n    User c\n"])
        #expect(Self.place("db.corp", configuration).point == .end)
        #expect(Self.place("web.corp", configuration).point == .before(line: 0))
    }

    @Test("A configuration with no Host block appends after its global directives")
    func noHostBlocks() async throws {
        let configuration = try await Self.configuration(["config": "ServerAliveInterval 30\n"])
        #expect(Self.place("new", configuration) == PlacementDecision(point: .end, precedingMatches: []))
    }

    // MARK: - 6.8 / 6.9

    @Test("Match blocks are disregarded when choosing where to go")
    func matchBlocksAreDisregarded() async throws {
        let configuration = try await Self.configuration(["config": "Match all\n    User m\n\nHost x\n"])
        #expect(Self.place("new", configuration).point == .end)
    }

    @Test("Never above the first Host or Match line, so global lines stay global")
    func neverAboveTheFirstHeader() async throws {
        let configuration = try await Self.configuration(["config": "Include nothing\n# about all\nHost *\n"])
        #expect(Self.place("new", configuration).point == .before(line: 2))
    }

    // MARK: - 6.10 preceding matches

    @Test("A matching block in a globally included file is reported, naming its file")
    func globalIncludeMatch() async throws {
        let directory = Self.keys.appending(path: "conf.d", directoryHint: .isDirectory)
        let configuration = try await Self.configuration(
            ["config": "Include conf.d/*\n\nHost *\n", "conf.d/work": "Host *.corp\n    User w\n"],
            directories: [directory: [directory.appending(path: "work")]]
        )

        let decision = Self.place("db.corp", configuration)
        #expect(decision.point == .before(line: 2))
        #expect(decision.precedingMatches.map(\.displayName) == ["*.corp"])
        #expect(decision.precedingMatches.map(\.file) == [directory.appending(path: "work")])
        #expect(decision.precedingMatches.map(\.isConditional) == [false])
    }

    @Test("A match in an earlier include counts only when its Host chain matches too")
    func hostChainMustMatch() async throws {
        // A `Host` block in `config` itself that includes a file always matches the alias when
        // its chain does, so the new block lands above it. The chain only matters one level
        // further down, through a global include.
        let configuration = try await Self.configuration([
            "config": "Include outer\n\nHost other\n",
            "outer": "Host web\n    Include inner\n",
            "inner": "Host *\n    User x\n",
        ])
        // `inner` only applies while connecting to `web`, so it does not precede `db`.
        #expect(Self.place("db", configuration).precedingMatches.isEmpty)
        // A second `web` would be rejected as a duplicate, but the chain logic is what counts.
        #expect(Self.place("web", configuration).precedingMatches.map(\.displayName) == ["web", "*"])
    }

    @Test("A match reached under a Match block is reported as possibly applying")
    func matchChainIsConditional() async throws {
        let configuration = try await Self.configuration([
            "config": "Match all\n    Include inner\n\nHost other\n",
            "inner": "Host db\n",
        ])
        let decision = Self.place("db", configuration)
        #expect(decision.precedingMatches.map(\.isConditional) == [true])
    }

    @Test("A matching include after the insertion point does not precede the new block")
    func laterIncludesDoNotPrecede() async throws {
        let configuration = try await Self.configuration([
            "config": "Host *\n    User all\n\nInclude later\n",
            "later": "Host db\n",
        ])
        #expect(Self.place("db", configuration).precedingMatches.isEmpty)
    }
}
