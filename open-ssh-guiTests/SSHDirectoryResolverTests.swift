import Foundation
import Testing

/// Every case is driven through a fabricated home directory and the in-memory reader, so no
/// rule here involves the process, the file system, the current user's home directory or a
/// literal SSH directory path.
@Suite("SSH directory resolution")
struct SSHDirectoryResolverTests {

    private static let home = URL(filePath: "/fabricated/home", directoryHint: .isDirectory)
    private static let overridden = URL(filePath: "/fabricated/scratch")
    private static let otherOverride = URL(filePath: "/fabricated/other-scratch")

    /// The directory the resolver defaults to, spelled using the resolver's own constant so
    /// no test hard-codes the SSH directory name.
    private static var defaultDirectory: URL {
        home.appending(path: SSHDirectoryResolver.directoryName)
    }

    private static func path(_ url: URL) -> String {
        url.path(percentEncoded: false)
    }

    // MARK: - 3.1 default

    @Test("With no override, resolution defaults to the SSH directory inside the given home")
    func defaultsToTheGivenHomeDirectory() async throws {
        let resolver = SSHDirectoryResolver(reader: InMemorySSHDirectoryReader())

        let resolved = try await resolver.resolve(
            launchEnvironment: LaunchEnvironment(arguments: [], environmentVariables: [:]),
            homeDirectory: Self.home
        ).get()

        #expect(resolved == SSHDirectory(url: Self.defaultDirectory))
    }

    @Test("The default directory is accepted without being validated, so a first run still resolves")
    func defaultDirectoryIsNotValidated() async throws {
        // The reader knows of no directory at all, yet resolution still succeeds: an absent
        // SSH directory is a legitimate first-run state and must surface later as
        // unreadable, not as a resolution failure.
        let resolver = SSHDirectoryResolver(reader: InMemorySSHDirectoryReader())

        let outcome = await resolver.resolve(
            launchEnvironment: LaunchEnvironment(arguments: [], environmentVariables: [:]),
            homeDirectory: Self.home
        )

        #expect(try outcome.get() == SSHDirectory(url: Self.defaultDirectory))
    }

    // MARK: - 3.2 / 3.3 / 3.4 overrides and precedence

    @Test("A launch-argument override is resolved to the path it carries")
    func launchArgumentOverrideIsHonoured() async throws {
        let resolver = SSHDirectoryResolver(
            reader: InMemorySSHDirectoryReader(directories: [Self.overridden: []])
        )

        let resolved = try await resolver.resolve(
            launchEnvironment: LaunchEnvironment(
                arguments: [LaunchEnvironment.overrideArgument, Self.path(Self.overridden)],
                environmentVariables: [:]
            ),
            homeDirectory: Self.home
        ).get()

        #expect(resolved == SSHDirectory(url: Self.overridden))
    }

    @Test("An environment-variable override is resolved to the path it carries")
    func environmentVariableOverrideIsHonoured() async throws {
        let resolver = SSHDirectoryResolver(
            reader: InMemorySSHDirectoryReader(directories: [Self.overridden: []])
        )

        let resolved = try await resolver.resolve(
            launchEnvironment: LaunchEnvironment(
                arguments: [],
                environmentVariables: [LaunchEnvironment.overrideVariable: Self.path(Self.overridden)]
            ),
            homeDirectory: Self.home
        ).get()

        #expect(resolved == SSHDirectory(url: Self.overridden))
    }

    @Test("When both channels are set, the launch argument wins")
    func launchArgumentBeatsEnvironmentVariable() async throws {
        let resolver = SSHDirectoryResolver(
            reader: InMemorySSHDirectoryReader(directories: [Self.overridden: [], Self.otherOverride: []])
        )

        let resolved = try await resolver.resolve(
            launchEnvironment: LaunchEnvironment(
                arguments: [LaunchEnvironment.overrideArgument, Self.path(Self.overridden)],
                environmentVariables: [LaunchEnvironment.overrideVariable: Self.path(Self.otherOverride)]
            ),
            homeDirectory: Self.home
        ).get()

        #expect(resolved == SSHDirectory(url: Self.overridden))
    }

    // MARK: - 3.5 loud failure, never a silent fallback

    @Test("An override naming a path that does not exist fails and names that path")
    func nonExistentOverrideFails() async {
        let missing = URL(filePath: "/fabricated/no-such-directory")
        let resolver = SSHDirectoryResolver(reader: InMemorySSHDirectoryReader())

        let outcome = await resolver.resolve(
            launchEnvironment: LaunchEnvironment(
                arguments: [LaunchEnvironment.overrideArgument, Self.path(missing)],
                environmentVariables: [:]
            ),
            homeDirectory: Self.home
        )

        #expect(outcome == .failure(.overridePathDoesNotExist(missing)))
    }

    @Test("An override naming a regular file fails as not-a-directory, distinct from absence")
    func overrideNamingARegularFileFails() async {
        let file = URL(filePath: "/fabricated/a-regular-file")
        let resolver = SSHDirectoryResolver(
            reader: InMemorySSHDirectoryReader(files: [file: Data()])
        )

        let outcome = await resolver.resolve(
            launchEnvironment: LaunchEnvironment(
                arguments: [LaunchEnvironment.overrideArgument, Self.path(file)],
                environmentVariables: [:]
            ),
            homeDirectory: Self.home
        )

        #expect(outcome == .failure(.overridePathIsNotADirectory(file)))
    }

    @Test("An invalid override never falls back to the home directory")
    func invalidOverrideNeverFallsBackToHome() async {
        let missing = URL(filePath: "/fabricated/no-such-directory")
        let resolver = SSHDirectoryResolver(
            reader: InMemorySSHDirectoryReader(directories: [Self.defaultDirectory: []])
        )

        let outcome = await resolver.resolve(
            launchEnvironment: LaunchEnvironment(
                arguments: [LaunchEnvironment.overrideArgument, Self.path(missing)],
                environmentVariables: [:]
            ),
            homeDirectory: Self.home
        )

        #expect((try? outcome.get()) == nil)
    }

    @Test("An invalid environment-variable override fails just as loudly as an argument one")
    func invalidVariableOverrideAlsoFails() async {
        let missing = URL(filePath: "/fabricated/no-such-directory")
        let resolver = SSHDirectoryResolver(reader: InMemorySSHDirectoryReader())

        let outcome = await resolver.resolve(
            launchEnvironment: LaunchEnvironment(
                arguments: [],
                environmentVariables: [LaunchEnvironment.overrideVariable: Self.path(missing)]
            ),
            homeDirectory: Self.home
        )

        #expect(outcome == .failure(.overridePathDoesNotExist(missing)))
    }

    // MARK: - 3.7 the resolver does not interpret `~` itself

    @Test("A tilde in an override is not expanded by the resolver, so it fails rather than guessing")
    func tildeIsNotExpanded() async {
        let resolver = SSHDirectoryResolver(
            reader: InMemorySSHDirectoryReader(directories: [Self.defaultDirectory: []])
        )

        let outcome = await resolver.resolve(
            launchEnvironment: LaunchEnvironment(
                arguments: [LaunchEnvironment.overrideArgument, "~/elsewhere"],
                environmentVariables: [:]
            ),
            homeDirectory: Self.home
        )

        #expect((try? outcome.get()) == nil)
    }

    @Test("A malformed override flag leaves the default in place rather than failing")
    func malformedOverrideFlagFallsBackToTheDefault() async throws {
        let resolver = SSHDirectoryResolver(reader: InMemorySSHDirectoryReader())

        let resolved = try await resolver.resolve(
            launchEnvironment: LaunchEnvironment(
                arguments: [LaunchEnvironment.overrideArgument],
                environmentVariables: [:]
            ),
            homeDirectory: Self.home
        ).get()

        #expect(resolved == SSHDirectory(url: Self.defaultDirectory))
    }
}
