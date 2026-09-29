import Foundation
import Testing

@Suite("Test support: in-memory reader and scratch directories")
struct TestSupportTests {

    @Test("A fabricated directory listing is readable with no file system involved")
    func fabricatedListingIsReadable() async throws {
        let directory = URL(filePath: "/fabricated/directory", directoryHint: .isDirectory)
        let entry = directory.appending(path: "config")
        let reader = InMemorySSHDirectoryReader(directories: [directory: [entry]])

        #expect(await reader.directoryExists(at: directory))
        #expect(try await reader.entries(in: directory) == [entry])
    }

    @Test("The in-memory reader reports a regular file as not a directory")
    func regularFileIsNotADirectory() async {
        let file = URL(filePath: "/fabricated/config")
        let reader = InMemorySSHDirectoryReader(files: [file: Data("Host example\n".utf8)])

        #expect(await reader.fileExists(at: file))
        #expect(await reader.directoryExists(at: file) == false)
    }

    @Test("The in-memory reader throws for a path it does not know")
    func unknownPathThrows() async {
        let missing = URL(filePath: "/fabricated/missing", directoryHint: .isDirectory)
        let reader = InMemorySSHDirectoryReader()

        await #expect(throws: FileAccessError.directoryNotFound(missing)) {
            try await reader.entries(in: missing)
        }
    }

    @Test("The in-memory reader can be told to fail a specific path")
    func scriptedFailureIsThrown() async {
        let denied = URL(filePath: "/fabricated/denied", directoryHint: .isDirectory)
        let reader = InMemorySSHDirectoryReader(failures: [denied: .accessDenied(denied)])

        await #expect(throws: FileAccessError.accessDenied(denied)) {
            try await reader.entries(in: denied)
        }
    }

    @Test("A scratch directory exists for the duration of the body")
    func scratchDirectoryExistsDuringBody() async throws {
        let observed = try await TemporaryDirectory.withOne { scratch in
            #expect(FileManager.default.fileExists(atPath: scratch.url.path(percentEncoded: false)))
            return scratch.url
        }

        #expect(FileManager.default.fileExists(atPath: observed.path(percentEncoded: false)) == false)
    }

    @Test("A scratch directory is removed even when its test fails")
    func scratchDirectoryIsRemovedOnTheFailurePath() async throws {
        struct DeliberateFailure: Error {}
        var leaked: URL?

        await #expect(throws: DeliberateFailure.self) {
            try await TemporaryDirectory.withOne { scratch in
                leaked = scratch.url
                throw DeliberateFailure()
            }
        }

        let path = try #require(leaked).path(percentEncoded: false)
        #expect(FileManager.default.fileExists(atPath: path) == false)
    }

    @Test("A scratch directory can be populated with files and subdirectories")
    func scratchDirectoryCanBePopulated() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let file = try scratch.file(named: "config", contents: Data("Host example\n".utf8))
            let nested = try scratch.subdirectory(named: "conf.d")

            #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: nested.path(percentEncoded: false)))
        }
    }

    @Test("Two scratch directories never collide, so parallel suites stay independent")
    func scratchDirectoriesAreDistinct() async throws {
        try await TemporaryDirectory.withOne { first in
            try await TemporaryDirectory.withOne { second in
                #expect(first.url != second.url)
            }
        }
    }
}
