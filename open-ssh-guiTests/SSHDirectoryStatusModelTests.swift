import Foundation
import Testing

/// Every state is driven through a fabricated reader. No test here involves the file
/// system, the process environment, the current user's home directory or a literal SSH
/// directory path.
@MainActor
@Suite("Menu bar status model")
struct SSHDirectoryStatusModelTests {

    private static let home = URL(filePath: "/fabricated/home", directoryHint: .isDirectory)
    private static let scratch = URL(filePath: "/fabricated/scratch")

    private static var defaultDirectory: URL {
        home.appending(path: SSHDirectoryResolver.directoryName)
    }

    nonisolated private static func noOverride() -> LaunchEnvironment {
        LaunchEnvironment(arguments: [], environmentVariables: [:])
    }

    private static func override(_ url: URL) -> LaunchEnvironment {
        LaunchEnvironment(
            arguments: [LaunchEnvironment.overrideArgument, url.path(percentEncoded: false)],
            environmentVariables: [:]
        )
    }

    private static func model(
        reader: some SSHDirectoryReading,
        launchEnvironment: LaunchEnvironment = noOverride()
    ) -> SSHDirectoryStatusModel {
        SSHDirectoryStatusModel(
            resolver: SSHDirectoryResolver(reader: reader),
            launchEnvironment: launchEnvironment,
            homeDirectory: home,
            reader: reader
        )
    }

    // MARK: - The four states

    @Test("Before the first refresh the model reports that it is still resolving")
    func startsOutResolving() {
        let model = Self.model(reader: InMemorySSHDirectoryReader())

        #expect(model.status == .resolving)
    }

    @Test("A readable directory becomes reachable")
    func readableDirectoryIsReachable() async {
        let reader = InMemorySSHDirectoryReader(directories: [Self.defaultDirectory: []])
        let model = Self.model(reader: reader)

        await model.refresh()

        #expect(model.status == .reachable(SSHDirectory(url: Self.defaultDirectory)))
    }

    @Test("An invalid override leaves the directory unresolved, naming the offending path")
    func invalidOverrideIsUnresolved() async {
        let missing = URL(filePath: "/fabricated/no-such-directory")
        let model = Self.model(
            reader: InMemorySSHDirectoryReader(),
            launchEnvironment: Self.override(missing)
        )

        await model.refresh()

        #expect(model.status == .unresolved(.overridePathDoesNotExist(missing)))
    }

    @Test("A resolved directory that cannot be read becomes unreadable, carrying the reason")
    func unreadableDirectoryCarriesTheReason() async {
        let reader = RecordingSSHDirectoryReader(
            knownDirectories: [Self.scratch],
            entriesResult: .failure(.accessDenied(Self.scratch))
        )
        let model = Self.model(reader: reader, launchEnvironment: Self.override(Self.scratch))

        await model.refresh()

        #expect(model.status == .unreadable(SSHDirectory(url: Self.scratch), .accessDenied(Self.scratch)))
    }

    @Test("An absent default directory surfaces as unreadable, not as a resolution failure")
    func absentDefaultDirectoryIsUnreadable() async {
        // Nothing exists anywhere, which is the first-run case: resolution still succeeds and
        // the listing is what reports the absence.
        let model = Self.model(reader: InMemorySSHDirectoryReader())

        await model.refresh()

        #expect(
            model.status == .unreadable(
                SSHDirectory(url: Self.defaultDirectory),
                .directoryNotFound(Self.defaultDirectory)
            )
        )
    }

    @Test("Refresh never throws, so the app keeps running whatever the file system says")
    func refreshAbsorbsEveryFailure() async {
        let reader = RecordingSSHDirectoryReader(
            knownDirectories: [Self.scratch],
            entriesResult: .failure(.unreadable(Self.scratch))
        )
        let model = Self.model(reader: reader, launchEnvironment: Self.override(Self.scratch))

        await model.refresh()

        #expect(model.status != .resolving)
    }

    // MARK: - 3.6 resolved once per launch

    @Test("A second refresh re-probes readability without resolving again")
    func secondRefreshReProbesWithoutReResolving() async {
        let reader = RecordingSSHDirectoryReader(knownDirectories: [Self.scratch])
        let model = Self.model(reader: reader, launchEnvironment: Self.override(Self.scratch))

        await model.refresh()
        let resolutionProbesAfterFirst = reader.directoryExistsCallCount
        await model.refresh()

        #expect(resolutionProbesAfterFirst == 1, "the first refresh should resolve exactly once")
        #expect(reader.directoryExistsCallCount == 1, "the second refresh must not resolve again")
        #expect(reader.entriesCallCount == 2, "the second refresh must re-probe readability")
    }

    @Test("Resolution is memoized even when it failed, so a bad override is not retried")
    func failedResolutionIsAlsoMemoized() async {
        let reader = RecordingSSHDirectoryReader()
        let model = Self.model(reader: reader, launchEnvironment: Self.override(Self.scratch))

        await model.refresh()
        await model.refresh()

        // One `directoryExists` probe per resolution attempt, plus one `fileExists` probe to
        // tell a regular file from an absent path — both served by the same counter here.
        #expect(reader.directoryExistsCallCount == 2, "a failed resolution must not be attempted twice")
        #expect(model.status == .unresolved(.overridePathDoesNotExist(Self.scratch)))
    }

    @Test("A directory that loses readability between refreshes is reported as unreadable")
    func readabilityIsReProbedEachRefresh() async {
        let reader = RecordingSSHDirectoryReader(knownDirectories: [Self.scratch])
        let model = Self.model(reader: reader, launchEnvironment: Self.override(Self.scratch))

        await model.refresh()
        #expect(model.status == .reachable(SSHDirectory(url: Self.scratch)))

        reader.setEntriesResult(.failure(.accessDenied(Self.scratch)))
        await model.refresh()

        #expect(model.status == .unreadable(SSHDirectory(url: Self.scratch), .accessDenied(Self.scratch)))
    }

    @Test("A directory that regains readability is reported as reachable again")
    func readabilityCanRecover() async {
        let reader = RecordingSSHDirectoryReader(
            knownDirectories: [Self.scratch],
            entriesResult: .failure(.accessDenied(Self.scratch))
        )
        let model = Self.model(reader: reader, launchEnvironment: Self.override(Self.scratch))

        await model.refresh()
        reader.setEntriesResult(.success([]))
        await model.refresh()

        #expect(model.status == .reachable(SSHDirectory(url: Self.scratch)))
    }

    @Test("The listing gathered while probing readability is discarded, so no file name is retained")
    func listingIsDiscarded() async {
        let entry = Self.scratch.appending(path: "id_ed25519")
        let reader = RecordingSSHDirectoryReader(
            knownDirectories: [Self.scratch],
            entriesResult: .success([entry])
        )
        let model = Self.model(reader: reader, launchEnvironment: Self.override(Self.scratch))

        await model.refresh()

        // `.reachable` carries the directory alone; there is nowhere for an entry to be kept.
        #expect(model.status == .reachable(SSHDirectory(url: Self.scratch)))
    }
}
