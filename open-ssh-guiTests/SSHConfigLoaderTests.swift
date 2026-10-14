import Foundation
import Testing

/// Loading follows `Include` exactly as `ssh` does — depth-first, at the directive's position,
/// globs in lexical order — over an in-memory reader. Nothing here touches the file system.
@Suite("Configuration loader")
nonisolated struct SSHConfigLoaderTests {

    private static let home = URL(filePath: "/fabricated/home", directoryHint: .isDirectory)
    private static let defaultDirectory = home.appending(path: SSHDirectoryResolver.directoryName, directoryHint: .isDirectory)
    private static let keys = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)

    private static func context(_ directory: URL) -> IdentityResolutionContext {
        IdentityResolutionContext(
            homeDirectory: home,
            sshDirectory: SSHDirectory(url: directory),
            userName: "alice",
            defaultDirectory: defaultDirectory
        )
    }

    private static func file(_ name: String, in directory: URL = keys) -> URL {
        directory.appending(path: name)
    }

    private static func subdirectory(_ name: String, in directory: URL = keys) -> URL {
        directory.appending(path: name, directoryHint: .isDirectory)
    }

    /// Loads from `files`, given as paths relative to `directory` and their text.
    private static func load(
        _ files: [String: String],
        directories: [URL: [URL]] = [:],
        failures: [URL: FileAccessError] = [:],
        in directory: URL = keys,
        reader wrap: (any SSHDirectoryReading) -> any SSHDirectoryReading = { $0 }
    ) async -> ConfigLoadOutcome {
        let reader = InMemorySSHDirectoryReader(
            directories: directories.merging([directory: []]) { existing, _ in existing },
            files: Dictionary(uniqueKeysWithValues: files.map { (file($0.key, in: directory), Data($0.value.utf8)) }),
            failures: failures
        )
        return await SSHConfigLoader(reader: wrap(reader), parser: SSHConfigParser())
            .load(in: SSHDirectory(url: directory), context: context(directory))
    }

    private static func configuration(_ outcome: ConfigLoadOutcome) throws -> SSHConfiguration {
        guard case .loaded(let configuration) = outcome else {
            Issue.record("expected a loaded configuration, got \(outcome)")
            throw CancellationError()
        }
        return configuration
    }

    // MARK: - 1.1 / 1.8 / 1.9 config itself

    @Test("No config file is its own outcome, distinct from one that cannot be read")
    func noConfigFile() async {
        #expect(await Self.load([:]) == .noConfigFile)
    }

    @Test("A config that exists but cannot be read reports why")
    func unreadableConfig() async {
        let config = Self.file("config")
        let outcome = await Self.load(["config": "Host a\n"], failures: [config: .accessDenied(config)])
        #expect(outcome == .unreadable(.accessDenied(config)))
    }

    @Test("A config with no includes is loaded as one file")
    func singleFile() async throws {
        let configuration = try Self.configuration(await Self.load(["config": "Host a\nHost b\n"]))

        #expect(configuration.files.map(\.url) == [Self.file("config")])
        #expect(configuration.entries.map(\.displayName) == ["a", "b"])
        #expect(configuration.issues.isEmpty)
    }

    // MARK: - 1.2 / 1.5 order and nesting

    @Test("Includes are followed depth-first, at the position each directive appears")
    func nestedIncludesInLoadOrder() async throws {
        let configuration = try Self.configuration(
            await Self.load([
                "config": "Host c0\nInclude a\nHost c1\n",
                "a": "Include b\nHost a0\n",
                "b": "Host b0\n",
            ])
        )

        #expect(configuration.entries.map(\.displayName) == ["c0", "b0", "a0", "c1"])
        #expect(configuration.files.map(\.url) == [Self.file("config"), Self.file("a"), Self.file("b")])
    }

    @Test("An Include inside a Host block is read, and its file remembers the condition")
    func includeInsideAHostBlock() async throws {
        let configuration = try Self.configuration(
            await Self.load([
                "config": "Host *.corp\n    Include corp\nHost z\n",
                "corp": "Host inside\n",
            ])
        )

        #expect(configuration.entries.map(\.displayName) == ["*.corp", "inside", "z"])
        let corp = try #require(configuration.file(at: Self.file("corp")))
        #expect(corp.inclusionChain == [.host([HostPattern(parsing: "*.corp")])])
    }

    // MARK: - 1.3 / 1.4 globs

    @Test("Glob matches are read in lexical order, and a dotfile is not matched by *")
    func globOrderAndLeadingDot() async throws {
        let directory = Self.subdirectory("conf.d")
        let configuration = try Self.configuration(
            await Self.load(
                [
                    "config": "Include conf.d/*\n",
                    "conf.d/b": "Host b\n",
                    "conf.d/a": "Host a\n",
                    "conf.d/.config.open-ssh-gui-backup": "Host backup\n",
                ],
                directories: [
                    directory: ["b", "a", ".config.open-ssh-gui-backup"].map { directory.appending(path: $0) },
                ]
            )
        )

        #expect(configuration.entries.map(\.displayName) == ["a", "b"])
        #expect(configuration.includePatterns == [GlobPath(path: "/fabricated/keys/conf.d/*")])
    }

    @Test("A wildcard in a directory segment is walked one level at a time")
    func multiLevelGlob() async throws {
        let one = Self.subdirectory("one")
        let two = Self.subdirectory("two")
        let configuration = try Self.configuration(
            await Self.load(
                [
                    "config": "Include */conf\n",
                    "one/conf": "Host one\n",
                    "two/conf": "Host two\n",
                ],
                directories: [
                    Self.keys: [two, one, Self.file("config")],
                    one: [one.appending(path: "conf")],
                    two: [two.appending(path: "conf")],
                ]
            )
        )

        #expect(configuration.entries.map(\.displayName) == ["one", "two"])
    }

    // MARK: - 1.6 / 1.9 missing and unreadable includes

    @Test("A missing included file is skipped silently, as ssh does")
    func missingIncludeIsSilent() async throws {
        let configuration = try Self.configuration(await Self.load(["config": "Include nothing\nHost a\n"]))

        #expect(configuration.entries.map(\.displayName) == ["a"])
        #expect(configuration.issues.isEmpty)
    }

    @Test("An unreadable include is reported with its file, and loading continues")
    func unreadableIncludeIsReported() async throws {
        let locked = Self.file("locked")
        let configuration = try Self.configuration(
            await Self.load(
                ["config": "Include locked\nInclude open\nHost a\n", "locked": "Host x\n", "open": "Host o\n"],
                failures: [locked: .accessDenied(locked)]
            )
        )

        #expect(configuration.entries.map(\.displayName) == ["o", "a"])
        #expect(configuration.issues == [.unreadable(file: locked, .accessDenied(locked))])
    }

    // MARK: - 1.7 cycles and depth

    @Test("A cycle stops at the file already on the chain, keeping everything read so far")
    func cycleIsStopped() async throws {
        let configuration = try Self.configuration(
            await Self.load(["config": "Include a\nHost c\n", "a": "Host a\nInclude config\n"])
        )

        #expect(configuration.entries.map(\.displayName) == ["a", "c"])
        #expect(configuration.issues == [.includeCycle(file: Self.file("config"))])
    }

    @Test("Nesting deeper than 16 stops at the 17th file, keeping the 16 before it")
    func depthLimit() async throws {
        var files = ["config": "Include f1\n"]
        for level in 1...17 {
            files["f\(level)"] = "Host h\(level)\nInclude f\(level + 1)\n"
        }

        let configuration = try Self.configuration(await Self.load(files))

        #expect(configuration.entries.map(\.displayName) == (1...16).map { "h\($0)" })
        #expect(configuration.issues == [.includeDepthExceeded(file: Self.file("f17"))])
    }

    // MARK: - 1.10 override confinement

    @Test("Under an override, an include outside it is reported and never read")
    func overrideConfinement() async throws {
        let outside = URL(filePath: "/fabricated/elsewhere/config")
        var auditor: AuditingSSHDirectoryReader?

        let configuration = try Self.configuration(
            await Self.load(["config": "Include /fabricated/elsewhere/config\nInclude ~/config\n"]) { reader in
                let auditing = AuditingSSHDirectoryReader(wrapping: reader)
                auditor = auditing
                return auditing
            }
        )

        #expect(configuration.issues == [
            .skippedInclude(file: Self.file("config"), line: 0, argument: "/fabricated/elsewhere/config", reason: .outsideOverride),
            .skippedInclude(file: Self.file("config"), line: 1, argument: "~/config", reason: .outsideOverride),
        ])
        let touched = try #require(auditor).allPaths.map { $0.path(percentEncoded: false) }
        #expect(!touched.contains(outside.path(percentEncoded: false)))
        #expect(!touched.contains { $0.hasPrefix(Self.home.path(percentEncoded: false)) })
    }

    @Test("An include the app cannot resolve is reported rather than guessed at")
    func unresolvableInclude() async throws {
        let configuration = try Self.configuration(await Self.load(["config": "Include %h.conf\n"]))
        #expect(configuration.issues == [
            .skippedInclude(file: Self.file("config"), line: 0, argument: "%h.conf", reason: .unresolvable(.connectionToken("%h"))),
        ])
    }

    @Test("In the default directory, a file outside it is read but read-only")
    func outsideFilesAreReadOnly() async throws {
        let system = URL(filePath: "/fabricated/system/extra")
        let reader = InMemorySSHDirectoryReader(
            directories: [Self.defaultDirectory: []],
            files: [
                Self.file("config", in: Self.defaultDirectory): Data("Include /fabricated/system/extra\n".utf8),
                system: Data("Host system\n".utf8),
            ]
        )

        let configuration = try Self.configuration(
            await SSHConfigLoader(reader: reader, parser: SSHConfigParser())
                .load(in: SSHDirectory(url: Self.defaultDirectory), context: Self.context(Self.defaultDirectory))
        )

        #expect(configuration.files.first?.writability == .writable)
        #expect(configuration.file(at: system)?.writability == .readOnly(.outsideDirectory))
        #expect(configuration.entries.first?.writability == .readOnly(.outsideDirectory))
    }

    // MARK: - 2.12 unparseable lines

    @Test("Every unparseable line becomes an issue naming its file and line")
    func unparseableLines() async throws {
        let configuration = try Self.configuration(
            await Self.load(["config": "Host a\n    User \"open\nInclude b\n", "b": "Port\n"])
        )

        #expect(configuration.issues == [
            .unparseableLine(file: Self.file("config"), line: 1, reason: .invalidQuotes),
            .unparseableLine(file: Self.file("b"), line: 0, reason: .missingArgument),
        ])
    }
}
