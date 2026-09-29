import Foundation

/// A `SSHDirectoryReading` conformer that counts what it was asked, and can be told to
/// change its answer between calls.
///
/// Counting is what makes memoization observable: resolution probes with
/// `directoryExists(at:)` and the readability check probes with `entries(in:)`, so the two
/// counts show whether a refresh re-resolved or merely re-probed. Each test creates its own
/// instance; nothing is shared between suites.
final class RecordingSSHDirectoryReader: SSHDirectoryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    private struct State {
        var knownDirectories: Set<String>
        var entriesResult: Result<[URL], FileAccessError>
        var directoryExistsCallCount = 0
        var entriesCallCount = 0
    }

    init(knownDirectories: [URL] = [], entriesResult: Result<[URL], FileAccessError> = .success([])) {
        state = State(
            knownDirectories: Set(knownDirectories.map { $0.standardizedFileURL.path(percentEncoded: false) }),
            entriesResult: entriesResult
        )
    }

    /// How many times resolution probed for a directory.
    var directoryExistsCallCount: Int {
        lock.withLock { state.directoryExistsCallCount }
    }

    /// How many times the readability check listed a directory.
    var entriesCallCount: Int {
        lock.withLock { state.entriesCallCount }
    }

    /// Changes what the next listing returns, so a test can make a reachable directory
    /// become unreadable between refreshes.
    func setEntriesResult(_ result: Result<[URL], FileAccessError>) {
        lock.withLock { state.entriesResult = result }
    }

    func directoryExists(at url: URL) async -> Bool {
        lock.withLock {
            state.directoryExistsCallCount += 1
            return state.knownDirectories.contains(url.standardizedFileURL.path(percentEncoded: false))
        }
    }

    func fileExists(at url: URL) async -> Bool {
        await directoryExists(at: url)
    }

    func entries(in url: URL) async throws(FileAccessError) -> [URL] {
        let result = lock.withLock {
            state.entriesCallCount += 1
            return state.entriesResult
        }
        switch result {
        case .success(let entries): return entries
        case .failure(let error): throw error
        }
    }

    func contents(of url: URL) async throws(FileAccessError) -> Data {
        throw .unreadable(url)
    }
}
