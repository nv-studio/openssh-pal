import Foundation

/// An `SSHKeyGenerating` conformer that returns a fabricated outcome and launches nothing.
///
/// No test in this suite runs `ssh-keygen`: generation is driven through this stub, which is
/// what lets the form's success, failure and in-flight states all be exercised without
/// writing a key anywhere.
///
/// It can also be made to hold, so that the state while generation is running — progress
/// shown, the generate control unavailable — is observable without a sleep.
nonisolated final class StubSSHKeyGenerator: SSHKeyGenerating, @unchecked Sendable {

    private let lock = NSLock()
    private var state: State

    private struct State {
        var outcome: Result<SSHKeyPair, SSHKeyGenerationError>
        var requests: [SSHKeyGenerationRequest] = []
        var passphrases: [Passphrase] = []
        var directories: [SSHDirectory] = []
        var isHolding = false
        var isReleased = false
        var waiter: CheckedContinuation<Void, Never>?
    }

    init(outcome: Result<SSHKeyPair, SSHKeyGenerationError>) {
        state = State(outcome: outcome)
    }

    /// Every request that arrived, so a test can assert what the form sent.
    var requests: [SSHKeyGenerationRequest] { lock.withLock { state.requests } }

    /// The passphrases that arrived. Present so a test can assert the form passed what the
    /// user typed; nothing in production records a passphrase anywhere.
    var passphrases: [Passphrase] { lock.withLock { state.passphrases } }

    var directories: [SSHDirectory] { lock.withLock { state.directories } }

    var callCount: Int { lock.withLock { state.requests.count } }

    /// Replaces the outcome of the next call.
    func setOutcome(_ outcome: Result<SSHKeyPair, SSHKeyGenerationError>) {
        lock.withLock { state.outcome = outcome }
    }

    /// Makes generation suspend until `release()` is called.
    func hold() {
        lock.withLock {
            state.isHolding = true
            state.isReleased = false
        }
    }

    /// Lets a held generation finish.
    func release() {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            state.isReleased = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume()
    }

    func generate(
        _ request: SSHKeyGenerationRequest,
        passphrase: Passphrase,
        in directory: SSHDirectory
    ) async throws(SSHKeyGenerationError) -> SSHKeyPair {
        let outcome: Result<SSHKeyPair, SSHKeyGenerationError> = lock.withLock {
            state.requests.append(request)
            state.passphrases.append(passphrase)
            state.directories.append(directory)
            return state.outcome
        }

        await waitWhileHolding()

        switch outcome {
        case .success(let pair): return pair
        case .failure(let error): throw error
        }
    }

    private func waitWhileHolding() async {
        let shouldWait = lock.withLock { state.isHolding && !state.isReleased }
        guard shouldWait else { return }

        await withCheckedContinuation { continuation in
            let alreadyReleased = lock.withLock { () -> Bool in
                if state.isReleased { return true }
                state.waiter = continuation
                return false
            }
            if alreadyReleased { continuation.resume() }
        }
    }
}
