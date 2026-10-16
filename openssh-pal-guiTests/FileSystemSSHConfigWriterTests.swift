import Foundation
import Testing

/// The adapter against a real file system — always a per-test scratch directory, never the
/// developer's own. These are the guarantees that cannot be faked: atomic replacement,
/// permission preservation, symbolic links surviving, exclusive creation, and nothing left
/// behind on failure.
@Suite("File-system configuration writer")
struct FileSystemSSHConfigWriterTests {

    private static let writer = FileSystemSSHConfigWriter()

    /// A scratch layout: an `ssh` directory the writes are confined to, and an `outside`
    /// directory beside it that they must never reach.
    private struct Layout {
        let directory: SSHDirectory
        let ssh: URL
        let outside: URL

        init(_ scratch: TemporaryDirectory) throws {
            ssh = try scratch.subdirectory(named: "ssh")
            outside = try scratch.subdirectory(named: "outside")
            directory = SSHDirectory(url: ssh)
        }

        func write(_ text: String, to name: String, mode: Int = 0o600, in folder: URL? = nil) throws -> URL {
            let url = (folder ?? ssh).appending(path: name)
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
            return url
        }
    }

    private static func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private static func text(of url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    private static func leftovers(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.contains(FileSystemSSHConfigWriter.temporaryMarker) }
    }

    // MARK: - 9.3 / 9.5 replace

    @Test("A replace writes the new contents and keeps the file's permissions", arguments: [0o600, 0o644, 0o400])
    func replaceKeepsPermissions(_ mode: Int) async throws {
        try await TemporaryDirectory.withOne { scratch in
            let layout = try Layout(scratch)
            let config = try layout.write("Host a\n", to: "config", mode: mode)

            try await Self.writer.replace(config, expecting: Data("Host a\n".utf8), with: Data("Host b\n".utf8), within: layout.directory)

            #expect(try Self.text(of: config) == "Host b\n")
            #expect(try Self.mode(of: config) == mode)
            #expect(try Self.leftovers(in: layout.ssh).isEmpty)
        }
    }

    @Test("A replace through a symbolic link writes the target and the link survives")
    func symbolicLinkSurvives() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let layout = try Layout(scratch)
            let real = try layout.write("Host a\n", to: "real-config")
            let link = layout.ssh.appending(path: "config")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

            try await Self.writer.replace(link, expecting: Data("Host a\n".utf8), with: Data("Host b\n".utf8), within: layout.directory)

            #expect(try Self.text(of: real) == "Host b\n")
            let destination = try FileManager.default.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))
            #expect(destination == real.path(percentEncoded: false))
        }
    }

    @Test("A symbolic link pointing outside the directory is refused, and its target untouched")
    func outwardLinkIsRefused() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let layout = try Layout(scratch)
            let target = try layout.write("Host a\n", to: "config", in: layout.outside)
            let link = layout.ssh.appending(path: "config")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            #expect(await Self.writer.resolvedLocation(of: link).lastPathComponent == "config")
            #expect(await Self.writer.resolvedLocation(of: link).deletingLastPathComponent().lastPathComponent == "outside")

            await #expect(throws: SSHConfigWriteError.outsideDirectory(link)) {
                try await Self.writer.replace(link, expecting: Data("Host a\n".utf8), with: Data("x".utf8), within: layout.directory)
            }
            #expect(try Self.text(of: target) == "Host a\n")
            #expect(try Self.leftovers(in: layout.outside).isEmpty)
        }
    }

    // MARK: - 9.6 / 9.7 mismatch and failure

    @Test("A file that changed since it was read is not written")
    func changedOnDisk() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let layout = try Layout(scratch)
            let config = try layout.write("Host edited-elsewhere\n", to: "config")

            await #expect(throws: SSHConfigWriteError.changedOnDisk(config)) {
                try await Self.writer.replace(config, expecting: Data("Host a\n".utf8), with: Data("x".utf8), within: layout.directory)
            }
            #expect(try Self.text(of: config) == "Host edited-elsewhere\n")
            #expect(try Self.leftovers(in: layout.ssh).isEmpty)
        }
    }

    @Test("A write that cannot complete leaves the target as it was and no temporary file behind")
    func failureLeavesNothingBehind() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let layout = try Layout(scratch)
            let config = try layout.write("Host a\n", to: "config")
            let path = layout.ssh.path(percentEncoded: false)

            // A directory that cannot be written to refuses the temporary file.
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path) }

            await #expect(throws: SSHConfigWriteError.accessDenied(config)) {
                try await Self.writer.replace(config, expecting: Data("Host a\n".utf8), with: Data("x".utf8), within: layout.directory)
            }
            #expect(try Self.text(of: config) == "Host a\n")
            #expect(try Self.leftovers(in: layout.ssh).isEmpty)
        }
    }

    @Test("A missing file is reported as missing")
    func missingFile() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let layout = try Layout(scratch)
            let config = layout.ssh.appending(path: "config")
            await #expect(throws: SSHConfigWriteError.notFound(config)) {
                try await Self.writer.replace(config, expecting: Data(), with: Data("x".utf8), within: layout.directory)
            }
        }
    }

    // MARK: - 6.12 create

    @Test("Create brings a file into existence readable and writable only by its owner")
    func createIsOwnerOnly() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let layout = try Layout(scratch)
            let config = layout.ssh.appending(path: "config")

            try await Self.writer.create(config, with: Data("Host new\n".utf8), within: layout.directory)

            #expect(try Self.text(of: config) == "Host new\n")
            #expect(try Self.mode(of: config) == 0o600)
            #expect(try Self.leftovers(in: layout.ssh).isEmpty)
        }
    }

    @Test("Create never replaces a file that already exists")
    func createIsExclusive() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let layout = try Layout(scratch)
            let config = try layout.write("Host existing\n", to: "config")

            await #expect(throws: SSHConfigWriteError.alreadyExists(config)) {
                try await Self.writer.create(config, with: Data("Host new\n".utf8), within: layout.directory)
            }
            #expect(try Self.text(of: config) == "Host existing\n")
            #expect(try Self.leftovers(in: layout.ssh).isEmpty)
        }
    }

    @Test("Create outside the directory is refused")
    func createOutsideIsRefused() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let layout = try Layout(scratch)
            let outside = layout.outside.appending(path: "config")
            await #expect(throws: SSHConfigWriteError.outsideDirectory(outside)) {
                try await Self.writer.create(outside, with: Data(), within: layout.directory)
            }
            #expect(!FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)))
        }
    }

    // MARK: - 9.4 backup

    @Test("A backup is created owner-only with the file's bytes, once, and never overwritten")
    func backupIsTakenOnce() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let layout = try Layout(scratch)
            let config = try layout.write("Host original\n", to: "config", mode: 0o644)
            let backup = layout.ssh.appending(path: ".config.openssh-pal-backup")

            #expect(try await Self.writer.backUpIfAbsent(config, to: backup, within: layout.directory) == .created)
            #expect(try Self.text(of: backup) == "Host original\n")
            #expect(try Self.mode(of: backup) == 0o600)

            try Data("Host changed\n".utf8).write(to: config)
            #expect(try await Self.writer.backUpIfAbsent(config, to: backup, within: layout.directory) == .alreadyPresent)
            #expect(try Self.text(of: backup) == "Host original\n")
            #expect(try Self.leftovers(in: layout.ssh).isEmpty)
        }
    }

    // MARK: - 9.11 off the main actor

    /// `nonisolated` alone would let a `@MainActor` caller drag the write onto the main actor.
    /// This blocks the main thread outright, so it fails if `@concurrent` is removed.
    @MainActor
    @Test("A write completes while the main actor is blocked")
    func writeCompletesWhileTheMainActorIsBlocked() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let layout = try Layout(scratch)
            let config = try layout.write("Host a\n", to: "config")
            let directory = layout.directory

            try #require(Thread.isMainThread, "this guard is meaningless unless it blocks the real main thread")

            let finished = DispatchSemaphore(value: 0)
            let write = Task.detached {
                defer { finished.signal() }
                try await FileSystemSSHConfigWriter().replace(
                    config,
                    expecting: Data("Host a\n".utf8),
                    with: Data("Host b\n".utf8),
                    within: directory
                )
            }

            let outcome = finished.wait(timeout: .now() + 5)
            #expect(outcome == .success, "the write could not complete while the main actor was blocked")

            try await write.value
            #expect(try Self.text(of: config) == "Host b\n")
        }
    }
}
