import Foundation
import Testing

/// The double has to honour the port's contract, or every model test built on it proves
/// nothing: a fake that accepted a stale baseline would let a lost-update bug pass.
@Suite("In-memory configuration writer")
nonisolated struct InMemorySSHConfigWriterTests {

    private static let directory = SSHDirectory(url: URL(filePath: "/fabricated/keys"))
    private static let config = URL(filePath: "/fabricated/keys/config")
    private static let original = Data("Host a\n".utf8)

    @Test("A replace whose expected bytes differ from the file is refused, and nothing changes")
    func staleBaselineIsRefused() async throws {
        let writer = InMemorySSHConfigWriter(files: [Self.config: Self.original])

        await #expect(throws: SSHConfigWriteError.changedOnDisk(Self.config)) {
            try await writer.replace(Self.config, expecting: Data("other".utf8), with: Data("new".utf8), within: Self.directory)
        }
        #expect(writer.contents(of: Self.config) == Self.original)
        #expect(writer.completedWriteCount == 0)
    }

    @Test("A replace against the current bytes writes the new contents")
    func matchingBaselineIsWritten() async throws {
        let writer = InMemorySSHConfigWriter(files: [Self.config: Self.original])

        try await writer.replace(Self.config, expecting: Self.original, with: Data("Host b\n".utf8), within: Self.directory)

        #expect(writer.contents(of: Self.config) == Data("Host b\n".utf8))
        #expect(writer.calls == [.replace(Self.config)])
    }

    @Test("An external change makes the next replace fail as changed on disk")
    func externalChange() async throws {
        let writer = InMemorySSHConfigWriter(files: [Self.config: Self.original])
        writer.simulateExternalChange(of: Self.config, to: Data("Host z\n".utf8))

        await #expect(throws: SSHConfigWriteError.changedOnDisk(Self.config)) {
            try await writer.replace(Self.config, expecting: Self.original, with: Data(), within: Self.directory)
        }
    }

    @Test("Create refuses a file that already exists")
    func createIsExclusive() async throws {
        let writer = InMemorySSHConfigWriter(files: [Self.config: Self.original])

        await #expect(throws: SSHConfigWriteError.alreadyExists(Self.config)) {
            try await writer.create(Self.config, with: Data(), within: Self.directory)
        }
        #expect(writer.contents(of: Self.config) == Self.original)
    }

    @Test("A backup is created once and then reported as already present")
    func backupIsTakenOnce() async throws {
        let writer = InMemorySSHConfigWriter(files: [Self.config: Self.original])
        let backup = URL(filePath: "/fabricated/keys/.config.open-ssh-gui-backup")

        #expect(try await writer.backUpIfAbsent(Self.config, to: backup, within: Self.directory) == .created)
        #expect(try await writer.backUpIfAbsent(Self.config, to: backup, within: Self.directory) == .alreadyPresent)
        #expect(writer.contents(of: backup) == Self.original)
    }

    @Test("Every method refuses a target outside the directory, following links first")
    func confinement() async throws {
        let outside = URL(filePath: "/fabricated/elsewhere/config")
        let link = URL(filePath: "/fabricated/keys/linked")
        let writer = InMemorySSHConfigWriter(files: [outside: Self.original], links: [link: outside])

        #expect(await writer.resolvedLocation(of: link) == outside)
        await #expect(throws: SSHConfigWriteError.outsideDirectory(link)) {
            try await writer.replace(link, expecting: Self.original, with: Data(), within: Self.directory)
        }
        await #expect(throws: SSHConfigWriteError.outsideDirectory(outside)) {
            try await writer.create(outside, with: Data(), within: Self.directory)
        }
        #expect(writer.contents(of: outside) == Self.original)
    }

    @Test("A scripted failure is thrown and leaves the file untouched")
    func scriptedFailure() async throws {
        let writer = InMemorySSHConfigWriter(files: [Self.config: Self.original])
        writer.setFailure(.accessDenied(Self.config), for: Self.config)

        await #expect(throws: SSHConfigWriteError.accessDenied(Self.config)) {
            try await writer.replace(Self.config, expecting: Self.original, with: Data(), within: Self.directory)
        }
        #expect(writer.contents(of: Self.config) == Self.original)
    }
}
