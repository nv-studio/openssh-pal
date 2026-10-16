import Foundation
import Testing

/// The whole stack — real adapter, real resolver, real model — driven over scratch
/// directories.
///
/// These cover the same paths the end-to-end launch checks exercise, without the pixels.
/// Every case supplies its own fabricated home directory, so nothing here reads the current
/// user's home directory or their real SSH directory.
@MainActor
@Suite("Composed stack over a real scratch directory")
struct SSHDirectoryIntegrationTests {

    private static func model(
        launchEnvironment: LaunchEnvironment,
        homeDirectory: URL
    ) -> SSHDirectoryStatusModel {
        let reader = FileSystemSSHDirectoryReader()
        return SSHDirectoryStatusModel(
            resolver: SSHDirectoryResolver(reader: reader),
            launchEnvironment: launchEnvironment,
            homeDirectory: homeDirectory,
            reader: reader
        )
    }

    private static func argumentOverride(_ url: URL) -> LaunchEnvironment {
        LaunchEnvironment(
            arguments: [LaunchEnvironment.overrideArgument, url.path(percentEncoded: false)],
            environmentVariables: [:]
        )
    }

    @Test("An override naming a real scratch directory is reported as reachable")
    func overriddenScratchDirectoryIsReachable() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let model = Self.model(
                launchEnvironment: Self.argumentOverride(scratch.url),
                homeDirectory: scratch.url
            )

            await model.refresh()

            #expect(model.status.isReachable)
            #expect(model.status.displayPath == scratch.url.standardizedFileURL.path(percentEncoded: false))
        }
    }

    @Test("The environment-variable channel works through the real stack too")
    func environmentVariableOverrideWorksEndToEnd() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let nested = try scratch.subdirectory(named: "elsewhere")
            let model = Self.model(
                launchEnvironment: LaunchEnvironment(
                    arguments: [],
                    environmentVariables: [
                        LaunchEnvironment.overrideVariable: nested.path(percentEncoded: false)
                    ]
                ),
                homeDirectory: scratch.url
            )

            await model.refresh()

            #expect(model.status.isReachable)
            #expect(model.status.displayPath == nested.standardizedFileURL.path(percentEncoded: false))
        }
    }

    @Test("An override naming a path that does not exist is unresolved and names that path")
    func missingOverrideIsUnresolvedEndToEnd() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let missing = scratch.url.appending(path: "no-such-directory")
            let model = Self.model(
                launchEnvironment: Self.argumentOverride(missing),
                homeDirectory: scratch.url
            )

            await model.refresh()

            let expected = missing.standardizedFileURL.path(percentEncoded: false)
            let reason = try #require(model.status.failureReason)
            #expect(model.status == .unresolved(.overridePathDoesNotExist(missing.standardizedFileURL)))
            #expect(model.status.displayPath == expected)
            #expect(reason.contains(expected))
        }
    }

    @Test("An override naming a real regular file is unresolved as not-a-directory")
    func fileOverrideIsUnresolvedEndToEnd() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let file = try scratch.file(named: "not-a-directory")
            let model = Self.model(
                launchEnvironment: Self.argumentOverride(file),
                homeDirectory: scratch.url
            )

            await model.refresh()

            #expect(model.status == .unresolved(.overridePathIsNotADirectory(file.standardizedFileURL)))
        }
    }

    @Test("With no override the default directory inside the given home is used")
    func defaultDirectoryIsUsedEndToEnd() async throws {
        try await TemporaryDirectory.withOne { scratch in
            // The scratch directory stands in for a home directory, so the default rule is
            // exercised against a real file system without going near the real one.
            try scratch.subdirectory(named: SSHDirectoryResolver.directoryName)
            // Spelled the way the resolver spells it — no trailing slash — since that is the
            // single form the resolved value carries.
            let expected = scratch.url.appending(path: SSHDirectoryResolver.directoryName)
            let model = Self.model(
                launchEnvironment: LaunchEnvironment(arguments: [], environmentVariables: [:]),
                homeDirectory: scratch.url
            )

            await model.refresh()

            #expect(model.status.isReachable)
            #expect(model.status.displayPath == expected.path(percentEncoded: false))
        }
    }

    @Test("A missing default directory is unreadable rather than a resolution failure")
    func missingDefaultDirectoryIsUnreadableEndToEnd() async throws {
        try await TemporaryDirectory.withOne { scratch in
            // The home stand-in contains no SSH directory at all: the first-run case.
            let model = Self.model(
                launchEnvironment: LaunchEnvironment(arguments: [], environmentVariables: [:]),
                homeDirectory: scratch.url
            )

            await model.refresh()

            let expected = scratch.url.appending(path: SSHDirectoryResolver.directoryName)
            #expect(model.status == .unreadable(SSHDirectory(url: expected), .directoryNotFound(expected)))
        }
    }

    @Test("A directory that disappears while the app runs becomes unreadable on the next refresh")
    func removedDirectoryBecomesUnreadable() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let target = try scratch.subdirectory(named: "vanishing")
            let model = Self.model(
                launchEnvironment: Self.argumentOverride(target),
                homeDirectory: scratch.url
            )

            await model.refresh()
            #expect(model.status.isReachable)

            try FileManager.default.removeItem(at: target)
            await model.refresh()

            #expect(model.status == .unreadable(
                SSHDirectory(url: target.standardizedFileURL),
                .directoryNotFound(target.standardizedFileURL)
            ))
        }
    }

    @Test("A directory that loses read permission reports denial, not absence")
    func unreadableDirectoryReportsDenialEndToEnd() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let target = try scratch.subdirectory(named: "locked")
            let path = target.path(percentEncoded: false)
            let model = Self.model(
                launchEnvironment: Self.argumentOverride(target),
                homeDirectory: scratch.url
            )

            await model.refresh()
            #expect(model.status.isReachable)

            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path) }
            await model.refresh()

            #expect(model.status == .unreadable(
                SSHDirectory(url: target.standardizedFileURL),
                .accessDenied(target.standardizedFileURL)
            ))
        }
    }
}
