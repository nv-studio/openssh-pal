import Foundation
import Testing

/// Exercises the real adapter against scratch directories only. No test here names the
/// current user's home directory or a literal SSH directory path.
@Suite("File-system adapter")
struct FileSystemSSHDirectoryReaderTests {

    @Test("Listing a populated directory returns its immediate children, dotfiles included")
    func listsImmediateChildren() async throws {
        try await TemporaryDirectory.withOne { scratch in
            try scratch.file(named: "config")
            try scratch.file(named: ".hidden")
            try scratch.subdirectory(named: "conf.d")
            let reader = FileSystemSSHDirectoryReader()

            let names = try await reader.entries(in: scratch.url).map(\.lastPathComponent).sorted()

            #expect(names == [".hidden", "conf.d", "config"])
        }
    }

    @Test("Listing an empty directory succeeds with no entries")
    func listsEmptyDirectory() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let reader = FileSystemSSHDirectoryReader()

            let entries = try await reader.entries(in: scratch.url)

            #expect(entries.isEmpty)
        }
    }

    @Test("A regular file is not a directory, though it does exist")
    func regularFileIsNotADirectory() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let file = try scratch.file(named: "config")
            let reader = FileSystemSSHDirectoryReader()

            #expect(await reader.fileExists(at: file))
            #expect(await reader.directoryExists(at: file) == false)
        }
    }

    @Test("A directory both exists and is a directory")
    func directoryIsRecognised() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let reader = FileSystemSSHDirectoryReader()

            #expect(await reader.fileExists(at: scratch.url))
            #expect(await reader.directoryExists(at: scratch.url))
        }
    }

    @Test("A missing path neither exists nor is a directory")
    func missingPathDoesNotExist() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let missing = scratch.url.appending(path: "missing", directoryHint: .isDirectory)
            let reader = FileSystemSSHDirectoryReader()

            #expect(await reader.fileExists(at: missing) == false)
            #expect(await reader.directoryExists(at: missing) == false)
        }
    }

    @Test("Listing a missing directory reports absence, not a generic failure")
    func missingDirectoryReportsAbsence() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let missing = scratch.url.appending(path: "missing", directoryHint: .isDirectory)
            let reader = FileSystemSSHDirectoryReader()

            await #expect(throws: FileAccessError.directoryNotFound(missing)) {
                try await reader.entries(in: missing)
            }
        }
    }

    @Test("Listing a regular file reports it as unreadable, distinct from absence")
    func listingARegularFileIsUnreadable() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let file = try scratch.file(named: "config")
            let reader = FileSystemSSHDirectoryReader()

            await #expect(throws: FileAccessError.unreadable(file)) {
                try await reader.entries(in: file)
            }
        }
    }

    @Test("Listing a directory the user cannot read reports denial, not absence")
    func unreadableDirectoryReportsDenial() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let locked = try scratch.subdirectory(named: "locked")
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path(percentEncoded: false))
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path(percentEncoded: false))
            }
            let reader = FileSystemSSHDirectoryReader()

            await #expect(throws: FileAccessError.accessDenied(locked)) {
                try await reader.entries(in: locked)
            }
        }
    }

    @Test("Reading a file returns its exact bytes")
    func readsFileContents() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let expected = Data("Host example\n    User someone\n".utf8)
            let file = try scratch.file(named: "config", contents: expected)
            let reader = FileSystemSSHDirectoryReader()

            let contents = try await reader.contents(of: file)

            #expect(contents == expected)
        }
    }

    @Test("Reading a missing file reports absence rather than empty data")
    func missingFileReportsAbsence() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let missing = scratch.url.appending(path: "missing")
            let reader = FileSystemSSHDirectoryReader()

            await #expect(throws: FileAccessError.directoryNotFound(missing)) {
                try await reader.contents(of: missing)
            }
        }
    }

    // MARK: - Isolation guard

    /// The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an unannotated
    /// adapter would be `@MainActor` and would run its file reads on the main actor while
    /// still satisfying the port's shape. `SWIFT_APPROACHABLE_CONCURRENCY` makes the
    /// resulting isolation mismatch a warning rather than an error, so the regression
    /// cannot be caught at compile time — it has to be observed at run time.
    ///
    /// The guard is to hold the main actor hostage: the read is started on a detached task
    /// and the main thread is then blocked outright. An adapter that needed the main actor
    /// could make no progress and the wait would time out; a `nonisolated` one finishes on
    /// the cooperative pool regardless. Drop `nonisolated` from the adapter and this test
    /// fails.
    @MainActor
    @Test("A read completes while the main actor is blocked")
    func readCompletesWhileTheMainActorIsBlocked() async throws {
        try await TemporaryDirectory.withOne { scratch in
            try scratch.file(named: "config")
            let url = scratch.url

            try #require(Thread.isMainThread, "this guard is meaningless unless it blocks the real main thread")

            let finished = DispatchSemaphore(value: 0)
            let read = Task.detached {
                defer { finished.signal() }
                return try await FileSystemSSHDirectoryReader().entries(in: url)
            }

            let outcome = finished.wait(timeout: .now() + 5)
            #expect(outcome == .success, "the read could not complete while the main actor was blocked")

            let names = try await read.value.map(\.lastPathComponent)
            #expect(names == ["config"])
        }
    }
}
