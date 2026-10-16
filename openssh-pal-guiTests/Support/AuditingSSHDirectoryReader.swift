import Foundation

/// Wraps another `SSHDirectoryReading` conformer and records every path it was asked about.
///
/// This exists for one assertion that cannot be made any other way: that no code path in the
/// feature ever reads a private key file. A fake that only answers questions can show what
/// the app did with the answers; this one shows which questions it asked, which is where that
/// guarantee actually lives.
nonisolated final class AuditingSSHDirectoryReader: SSHDirectoryReading, @unchecked Sendable {

    private let wrapped: any SSHDirectoryReading
    private let lock = NSLock()
    private var state = State()

    private struct State {
        var contentsRead: [URL] = []
        var listed: [URL] = []
        var probed: [URL] = []
    }

    init(wrapping wrapped: any SSHDirectoryReading) {
        self.wrapped = wrapped
    }

    /// Every path whose *contents* were read. The one list that matters for key material.
    var contentsRead: [URL] { lock.withLock { state.contentsRead } }

    /// Every directory that was listed.
    var listed: [URL] { lock.withLock { state.listed } }

    /// Every path that was probed for existence. A probe reads no bytes.
    var probed: [URL] { lock.withLock { state.probed } }

    /// Every path this reader was pointed at in any capacity.
    var allPaths: [URL] {
        lock.withLock { state.contentsRead + state.listed + state.probed }
    }

    func directoryExists(at url: URL) async -> Bool {
        lock.withLock { state.probed.append(url) }
        return await wrapped.directoryExists(at: url)
    }

    func fileExists(at url: URL) async -> Bool {
        lock.withLock { state.probed.append(url) }
        return await wrapped.fileExists(at: url)
    }

    func entries(in url: URL) async throws(FileAccessError) -> [URL] {
        lock.withLock { state.listed.append(url) }
        return try await wrapped.entries(in: url)
    }

    func contents(of url: URL) async throws(FileAccessError) -> Data {
        lock.withLock { state.contentsRead.append(url) }
        return try await wrapped.contents(of: url)
    }
}
