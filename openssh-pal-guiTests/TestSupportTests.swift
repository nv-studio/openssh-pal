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

/// Smoke tests for the doubles the key-management suites drive. Each is exercised through
/// its port, so a double that stopped conforming fails here rather than in every suite that
/// uses it.
@Suite("Test support: mutation, generation and clipboard doubles")
struct KeyPortDoublesTests {

    private static let directory = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)

    private static func name(_ raw: String) throws -> SSHKeyName {
        try SSHKeyName.validated(raw).get()
    }

    private static func pair(_ raw: String) throws -> SSHKeyPair {
        let name = try name(raw)
        return SSHKeyPair(
            location: SSHKeyPairLocation(
                name: name,
                publicKeyURL: name.publicKeyURL(in: directory),
                privateKeyURL: name.privateKeyURL(in: directory),
                certificateURL: nil
            ),
            publicKey: .success(
                SSHPublicKey(
                    algorithm: .ed25519,
                    bitLength: 256,
                    fingerprint: SSHFingerprint(value: "SHA256:fabricated"),
                    comment: nil
                )
            )
        )
    }

    @Test("The in-memory writer records a move and a removal without touching a file")
    func writerRecordsWhatItWasAsked() async throws {
        let writer = InMemorySSHKeyWriter()
        let from = Self.directory.appending(path: "old")
        let to = Self.directory.appending(path: "new")

        try await writer.move(from: from, to: to)
        try await writer.remove(at: to)

        #expect(writer.moves == [InMemorySSHKeyWriter.Move(from: from, to: to)])
        #expect(writer.removals == [to])
        #expect(writer.completedMutationCount == 2)
    }

    @Test("The in-memory writer fails exactly the path it was told to, so rollback is deterministic")
    func writerFailsOnlyTheChosenPath() async throws {
        let doomed = Self.directory.appending(path: "doomed")
        let fine = Self.directory.appending(path: "fine")
        let writer = InMemorySSHKeyWriter(failures: [doomed: .accessDenied(doomed)])

        try await writer.move(from: fine, to: Self.directory.appending(path: "fine2"))

        await #expect(throws: SSHKeyWriteError.accessDenied(doomed)) {
            try await writer.move(from: doomed, to: Self.directory.appending(path: "doomed2"))
        }

        // The failed move was attempted but did not complete, which is the distinction a
        // bystander-safety assertion needs.
        #expect(writer.moves.count == 1)
        #expect(writer.attemptedMoves.count == 2)
    }

    @Test("A failure can be scripted between calls, so a failing rollback is reachable")
    func writerFailureCanBeScriptedLater() async throws {
        let target = Self.directory.appending(path: "target")
        let writer = InMemorySSHKeyWriter()

        try await writer.move(from: target, to: Self.directory.appending(path: "moved"))
        writer.setFailure(.failed(target), for: target)

        await #expect(throws: SSHKeyWriteError.failed(target)) {
            try await writer.move(from: target, to: Self.directory.appending(path: "again"))
        }
    }

    @Test("The stub generator returns a fabricated pair and records what it was sent")
    func stubGeneratorReturnsAFabricatedPair() async throws {
        let expected = try Self.pair("work_key")
        let generator = StubSSHKeyGenerator(outcome: .success(expected))
        let request = SSHKeyGenerationRequest(name: try Self.name("work_key"), type: .ed25519, comment: "c")

        let produced = try await generator.generate(
            request,
            passphrase: Passphrase("secret"),
            in: SSHDirectory(url: Self.directory)
        )

        #expect(produced == expected)
        #expect(generator.requests == [request])
        #expect(generator.passphrases == [Passphrase("secret")])
        #expect(generator.directories == [SSHDirectory(url: Self.directory)])
    }

    @Test("The stub generator can fail instead, without launching anything")
    func stubGeneratorCanFail() async {
        let generator = StubSSHKeyGenerator(outcome: .failure(.timedOut))

        await #expect(throws: SSHKeyGenerationError.timedOut) {
            try await generator.generate(
                SSHKeyGenerationRequest(name: try Self.name("k"), type: .ed25519, comment: ""),
                passphrase: .none,
                in: SSHDirectory(url: Self.directory)
            )
        }
    }

    @Test("The stub generator can be held, so the in-flight state is observable without sleeping")
    func stubGeneratorCanBeHeld() async throws {
        let expected = try Self.pair("work_key")
        let generator = StubSSHKeyGenerator(outcome: .success(expected))
        generator.hold()

        let task = Task {
            try await generator.generate(
                SSHKeyGenerationRequest(name: try Self.name("work_key"), type: .ed25519, comment: ""),
                passphrase: .none,
                in: SSHDirectory(url: Self.directory)
            )
        }

        // The call has not returned; releasing is what lets it.
        generator.release()

        #expect(try await task.value == expected)
    }

    @Test("The clipboard recorder holds what was written and starts empty")
    func clipboardRecorderRecords() async {
        let clipboard = RecordingClipboardWriter()

        #expect(clipboard.isEmpty)

        await clipboard.write("ssh-ed25519 AAAA user@host")

        #expect(clipboard.writes == ["ssh-ed25519 AAAA user@host"])
        #expect(clipboard.lastWrite == "ssh-ed25519 AAAA user@host")
    }
}
