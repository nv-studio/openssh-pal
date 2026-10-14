import Foundation

/// An `SSHConfigWriting` conformer that holds file contents in memory and records every call.
///
/// It honours the port's contract — confinement after following links, compare-then-replace,
/// exclusive create, backup-once — so a model test built on it fails for the same reasons the
/// real adapter would refuse. It can also simulate the two things a model must survive: a file
/// edited behind its back, and a write that fails.
///
/// Internally locked rather than immutable, because recording is the point. Each test creates
/// its own instance; nothing is shared between parallel suites.
nonisolated final class InMemorySSHConfigWriter: SSHConfigWriting, @unchecked Sendable {

    enum Call: Equatable, Sendable {
        case backUp(URL, to: URL)
        case replace(URL)
        case create(URL)
    }

    private let lock = NSLock()
    private var state: State

    private struct State {
        var files: [String: Data]
        var links: [String: URL]
        var failures: [String: SSHConfigWriteError] = [:]
        var calls: [Call] = []
        var completedWrites = 0
        var isHolding = false
        var isReleased = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    /// - Parameters:
    ///   - files: the contents each fabricated file starts with.
    ///   - links: symbolic links, from the link's location to its target.
    init(files: [URL: Data] = [:], links: [URL: URL] = [:]) {
        state = State(files: files.keyedByPath(), links: links.keyedByPath())
    }

    // MARK: - Inspection

    func contents(of url: URL) -> Data? {
        lock.withLock { state.files[url.locationKey] }
    }

    /// Every call, in order, whether or not it succeeded.
    var calls: [Call] { lock.withLock { state.calls } }

    /// Writes that changed something: a created backup, a replace or a create.
    var completedWriteCount: Int { lock.withLock { state.completedWrites } }

    /// Every path a call named, as a target or a backup.
    var touchedPaths: [URL] {
        calls.flatMap { call -> [URL] in
            switch call {
            case .backUp(let file, let backup): [file, backup]
            case .replace(let file), .create(let file): [file]
            }
        }
    }

    // MARK: - Scripting

    /// Changes a file as a text editor would, without the model knowing.
    func simulateExternalChange(of url: URL, to contents: Data) {
        lock.withLock { state.files[url.locationKey] = contents }
    }

    /// Makes every later call on `url` fail with `error`, or clears that.
    func setFailure(_ error: SSHConfigWriteError?, for url: URL) {
        lock.withLock { state.failures[url.locationKey] = error }
    }

    /// Makes every mutation suspend until `release()`, so the in-flight state is observable.
    func hold() {
        lock.withLock {
            state.isHolding = true
            state.isReleased = false
        }
    }

    func release() {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            state.isReleased = true
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters { waiter.resume() }
    }

    private func waitWhileHolding() async {
        let shouldWait = lock.withLock { state.isHolding && !state.isReleased }
        guard shouldWait else { return }

        await withCheckedContinuation { continuation in
            let alreadyReleased = lock.withLock { () -> Bool in
                if state.isReleased { return true }
                state.waiters.append(continuation)
                return false
            }
            if alreadyReleased { continuation.resume() }
        }
    }

    // MARK: - SSHConfigWriting

    func resolvedLocation(of url: URL) async -> URL {
        lock.withLock { resolved(url) }
    }

    func backUpIfAbsent(
        _ file: URL,
        to backup: URL,
        within directory: SSHDirectory
    ) async throws(SSHConfigWriteError) -> BackupOutcome {
        await waitWhileHolding()
        let result: Result<BackupOutcome, SSHConfigWriteError> = lock.withLock {
            state.calls.append(.backUp(file, to: backup))
            if let failure = scriptedFailure(for: file) ?? scriptedFailure(for: backup) { return .failure(failure) }
            guard isInside(resolved(file), directory) else { return .failure(.outsideDirectory(file)) }
            guard isInside(resolved(backup), directory) else { return .failure(.outsideDirectory(backup)) }
            guard let contents = state.files[resolved(file).locationKey] else { return .failure(.notFound(file)) }
            if state.files[backup.locationKey] != nil { return .success(.alreadyPresent) }
            state.files[backup.locationKey] = contents
            state.completedWrites += 1
            return .success(.created)
        }
        return try result.get()
    }

    func replace(
        _ file: URL,
        expecting expected: Data,
        with contents: Data,
        within directory: SSHDirectory
    ) async throws(SSHConfigWriteError) {
        await waitWhileHolding()
        let failure: SSHConfigWriteError? = lock.withLock {
            state.calls.append(.replace(file))
            if let failure = scriptedFailure(for: file) { return failure }
            let target = resolved(file)
            guard isInside(target, directory) else { return .outsideDirectory(file) }
            guard let current = state.files[target.locationKey] else { return .notFound(file) }
            guard current == expected else { return .changedOnDisk(file) }
            state.files[target.locationKey] = contents
            state.completedWrites += 1
            return nil
        }
        if let failure { throw failure }
    }

    func create(_ file: URL, with contents: Data, within directory: SSHDirectory) async throws(SSHConfigWriteError) {
        await waitWhileHolding()
        let failure: SSHConfigWriteError? = lock.withLock {
            state.calls.append(.create(file))
            if let failure = scriptedFailure(for: file) { return failure }
            guard isInside(resolved(file), directory) else { return .outsideDirectory(file) }
            guard state.files[file.locationKey] == nil else { return .alreadyExists(file) }
            state.files[file.locationKey] = contents
            state.completedWrites += 1
            return nil
        }
        if let failure { throw failure }
    }

    // MARK: - Helpers, called with the lock held

    private func resolved(_ url: URL) -> URL {
        state.links[url.locationKey] ?? url.standardizedFileURL
    }

    private func scriptedFailure(for url: URL) -> SSHConfigWriteError? {
        state.failures[url.locationKey]
    }

    private func isInside(_ url: URL, _ directory: SSHDirectory) -> Bool {
        let root = directory.url.locationKey
        return url.locationKey.hasPrefix(root + "/")
    }
}

nonisolated extension URL {
    /// One spelling per location, with no trailing slash, so a fixture and a derived path
    /// match.
    fileprivate var locationKey: String {
        let path = standardizedFileURL.path(percentEncoded: false)
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
}

nonisolated extension Dictionary where Key == URL {
    fileprivate func keyedByPath() -> [String: Value] {
        Dictionary<String, Value>(map { ($0.key.locationKey, $0.value) }, uniquingKeysWith: { _, latest in latest })
    }
}
