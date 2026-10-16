import Foundation
import Testing

/// The one adapter that mutates a file, exercised against a scratch directory. Nothing here
/// goes near the real SSH directory: every path comes from `TemporaryDirectory`.
@Suite("File system key writer")
struct FileSystemSSHKeyWriterTests {

    private static let writer = FileSystemSSHKeyWriter()

    private static func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return try #require(attributes[.posixPermissions] as? NSNumber).intValue
    }

    // MARK: - 11.4 permissions survive a move

    @Test("A moved file keeps the permissions it had, so a private key stays owner-only")
    func moveKeepsPermissions() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let source = try scratch.file(named: "id_key", contents: Data("private".utf8))
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path(percentEncoded: false))
            let destination = scratch.url.appending(path: "renamed_key")

            try await Self.writer.move(from: source, to: destination)

            #expect(try Self.permissions(of: destination) == 0o600)
            #expect(!FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
        }
    }

    @Test("A public key's own permissions survive a move too, rather than being normalised")
    func moveKeepsPublicKeyPermissions() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let source = try scratch.file(named: "id_key.pub", contents: Data("public".utf8))
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: source.path(percentEncoded: false))
            let destination = scratch.url.appending(path: "renamed_key.pub")

            try await Self.writer.move(from: source, to: destination)

            #expect(try Self.permissions(of: destination) == 0o644)
        }
    }

    @Test("A move carries the file's contents across unchanged")
    func moveDoesNotChangeContents() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let contents = Data("ssh-ed25519 AAAA user@host\n".utf8)
            let source = try scratch.file(named: "id_key.pub", contents: contents)
            let destination = scratch.url.appending(path: "renamed.pub")

            try await Self.writer.move(from: source, to: destination)

            #expect(try Data(contentsOf: destination) == contents)
        }
    }

    // MARK: - 11.2 an existing destination is never replaced

    @Test("An existing destination is refused, and its contents are left intact")
    func existingDestinationIsRefused() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let source = try scratch.file(named: "newcomer", contents: Data("newcomer".utf8))
            let bystander = try scratch.file(named: "bystander", contents: Data("bystander".utf8))

            await #expect(throws: SSHKeyWriteError.destinationExists(bystander)) {
                try await Self.writer.move(from: source, to: bystander)
            }

            // The platform's own refusal is the backstop beneath name validation: even a
            // defective validator cannot destroy this file through the writer.
            #expect(try Data(contentsOf: bystander) == Data("bystander".utf8))
            #expect(try Data(contentsOf: source) == Data("newcomer".utf8))
        }
    }

    // MARK: - absence and denial stay distinguishable

    @Test("Moving a file that is not there reports absence, naming the file that was missing")
    func missingSourceReportsAbsence() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let missing = scratch.url.appending(path: "missing")

            await #expect(throws: SSHKeyWriteError.notFound(missing)) {
                try await Self.writer.move(from: missing, to: scratch.url.appending(path: "elsewhere"))
            }
        }
    }

    @Test("Removing a file that is not there reports absence rather than succeeding quietly")
    func missingRemovalReportsAbsence() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let missing = scratch.url.appending(path: "missing")

            await #expect(throws: SSHKeyWriteError.notFound(missing)) {
                try await Self.writer.remove(at: missing)
            }
        }
    }

    @Test("A denied move reports denial, not absence, because the user's next step differs")
    func deniedMoveReportsDenial() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let locked = try scratch.subdirectory(named: "locked")
            let source = locked.appending(path: "id_key")
            try Data("private".utf8).write(to: source)

            let path = locked.path(percentEncoded: false)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path)
            // Restored unconditionally, so the scratch directory can still be removed.
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path) }

            await #expect(throws: SSHKeyWriteError.accessDenied(source)) {
                try await Self.writer.move(from: source, to: locked.appending(path: "renamed"))
            }
        }
    }

    @Test("A denied removal reports denial")
    func deniedRemovalReportsDenial() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let locked = try scratch.subdirectory(named: "locked")
            let target = locked.appending(path: "id_key")
            try Data("private".utf8).write(to: target)

            let path = locked.path(percentEncoded: false)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path) }

            await #expect(throws: SSHKeyWriteError.accessDenied(target)) {
                try await Self.writer.remove(at: target)
            }
        }
    }

    // MARK: - 7.3 a removal removes exactly one file

    @Test("A removal removes the file it named and nothing beside it")
    func removalRemovesExactlyOneFile() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let target = try scratch.file(named: "id_key")
            let neighbour = try scratch.file(named: "id_key.pub")

            try await Self.writer.remove(at: target)

            #expect(!FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: neighbour.path(percentEncoded: false)))
        }
    }

    // MARK: - Isolation guard

    /// The same guard `FileSystemSSHDirectoryReaderTests` carries, for the same reason:
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise make this adapter run its
    /// mutations on the main actor while still satisfying the port's shape, and
    /// `SWIFT_APPROACHABLE_CONCURRENCY` reduces the resulting mismatch to a warning. So it is
    /// asserted at run time: the main thread is blocked outright, and a mutation that needed
    /// it could make no progress.
    ///
    /// Remove `@concurrent` from `move` and this test fails.
    @MainActor
    @Test("A mutation completes while the main actor is blocked")
    func mutationCompletesWhileTheMainActorIsBlocked() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let source = try scratch.file(named: "id_key")
            let destination = scratch.url.appending(path: "renamed_key")

            try #require(Thread.isMainThread, "this guard is meaningless unless it blocks the real main thread")

            let finished = DispatchSemaphore(value: 0)
            let move = Task.detached {
                defer { finished.signal() }
                try await FileSystemSSHKeyWriter().move(from: source, to: destination)
            }

            let outcome = finished.wait(timeout: .now() + 5)
            #expect(outcome == .success, "the mutation could not complete while the main actor was blocked")

            try await move.value
            #expect(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
        }
    }
}
