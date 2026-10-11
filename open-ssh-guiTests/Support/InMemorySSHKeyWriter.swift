import Foundation

/// An `SSHKeyWriting` conformer that records what it was asked to do and touches no file.
///
/// Recording attempts *and* completions separately is what lets two different questions be
/// asked: "did the directory end up as it should?" and the stronger "was a file outside the
/// pair even reached for?" — which is how bystander safety is asserted rather than assumed.
///
/// Internally locked rather than immutable, because recording is the point. Each test creates
/// its own instance; nothing is shared between parallel suites.
nonisolated final class InMemorySSHKeyWriter: SSHKeyWriting, @unchecked Sendable {

    struct Move: Equatable, Sendable {
        let from: URL
        let to: URL
    }

    private let lock = NSLock()
    private var state: State

    private struct State {
        var failures: [String: SSHKeyWriteError]
        var attemptedMoves: [Move] = []
        var attemptedRemovals: [URL] = []
        var moves: [Move] = []
        var removals: [URL] = []
        var isHolding = false
        var isReleased = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    /// - Parameter failures: paths that should fail, and the failure each produces. A move
    ///   is keyed by its source, a removal by the file it would remove — which is enough to
    ///   fail one chosen step of a plan and let the rest succeed.
    init(failures: [URL: SSHKeyWriteError] = [:]) {
        state = State(failures: failures.keyedByPath())
    }

    /// Moves that completed.
    var moves: [Move] { lock.withLock { state.moves } }

    /// Removals that completed.
    var removals: [URL] { lock.withLock { state.removals } }

    /// Moves that were asked for, whether or not they succeeded.
    var attemptedMoves: [Move] { lock.withLock { state.attemptedMoves } }

    /// Removals that were asked for, whether or not they succeeded.
    var attemptedRemovals: [URL] { lock.withLock { state.attemptedRemovals } }

    /// Every path this writer was pointed at, in any capacity.
    var touchedPaths: [URL] {
        lock.withLock {
            state.attemptedMoves.flatMap { [$0.from, $0.to] } + state.attemptedRemovals
        }
    }

    /// How many operations completed, so "nothing happened" is one assertion rather than two.
    var completedMutationCount: Int {
        lock.withLock { state.moves.count + state.removals.count }
    }

    /// Makes every mutation suspend until `release()` is called, so the state while an
    /// operation is in flight is observable without a sleep.
    func hold() {
        lock.withLock {
            state.isHolding = true
            state.isReleased = false
        }
    }

    /// Lets every held mutation proceed.
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

    /// Scripts or clears a failure between calls, for a rollback that must itself fail.
    func setFailure(_ error: SSHKeyWriteError?, for url: URL) {
        lock.withLock { state.failures[url.resolvedPath] = error }
    }

    func move(from source: URL, to destination: URL) async throws(SSHKeyWriteError) {
        await waitWhileHolding()
        let failure: SSHKeyWriteError? = lock.withLock {
            state.attemptedMoves.append(Move(from: source, to: destination))
            if let failure = state.failures[source.resolvedPath] { return failure }
            state.moves.append(Move(from: source, to: destination))
            return nil
        }
        if let failure { throw failure }
    }

    func remove(at url: URL) async throws(SSHKeyWriteError) {
        await waitWhileHolding()
        let failure: SSHKeyWriteError? = lock.withLock {
            state.attemptedRemovals.append(url)
            if let failure = state.failures[url.resolvedPath] { return failure }
            state.removals.append(url)
            return nil
        }
        if let failure { throw failure }
    }
}

nonisolated extension URL {
    /// One spelling per location, so a fixture and a derived path match.
    fileprivate var resolvedPath: String {
        standardizedFileURL.path(percentEncoded: false)
    }
}

nonisolated extension Dictionary where Key == URL {
    fileprivate func keyedByPath() -> [String: Value] {
        Dictionary<String, Value>(
            map { ($0.key.resolvedPath, $0.value) },
            uniquingKeysWith: { _, latest in latest }
        )
    }
}
