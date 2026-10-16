import Foundation

/// The production `SSHKeyGenerating` conformer: `ssh-keygen`, launched as a subprocess.
///
/// Four decisions in here are security properties rather than implementation details, and
/// each is a line someone could "simplify" away:
///
/// 1. **The tool is launched at an absolute, injected path**, never resolved through `PATH`.
///    A `PATH` lookup would let a hijacked `PATH` choose the binary that receives the user's
///    passphrase.
/// 2. **The passphrase goes in on piped standard input** — never `-N`, never the environment
///    — so it cannot be read out of a process listing. The environment is emptied outright.
/// 3. **One buffer is written twice.** `ssh-keygen` prompts for the passphrase and then for
///    its confirmation; writing the same bytes to both means the two cannot differ, so the
///    path where a mismatch silently produces an *unencrypted* key is unreachable rather
///    than detected after the fact.
/// 4. **Exit status alone is not proof of success.** The acceptance gate is exit 0 *and* both
///    files present *and* the public key, parsed from the file actually written, reporting
///    the algorithm and size that were requested.
///
/// `nonisolated` on the type and `@concurrent` on the method are both load-bearing, for the
/// reasons `FileSystemSSHDirectoryReader` documents.
nonisolated struct ProcessSSHKeyGenerator: SSHKeyGenerating {

    private let toolURL: URL
    private let reader: SSHDirectoryReading
    private let writer: SSHKeyWriting
    private let parser: SSHPublicKeyParser
    private let timeout: Duration

    /// - Parameters:
    ///   - toolURL: the absolute path to `ssh-keygen`. No default: a wrong default here would
    ///     be a binary the app hands a passphrase to.
    ///   - reader: used to confirm the target directory exists and to read back what was
    ///     written. Nothing here reads a private key's contents.
    ///   - writer: used only to remove output this generator itself produced and then
    ///     rejected.
    ///   - parser: verifies the generated public key against the request.
    ///   - timeout: bounds the whole operation, so a tool that neither finishes nor fails
    ///     cannot wedge the app.
    init(
        toolURL: URL,
        reader: SSHDirectoryReading,
        writer: SSHKeyWriting,
        parser: SSHPublicKeyParser,
        timeout: Duration = .seconds(30)
    ) {
        self.toolURL = toolURL
        self.reader = reader
        self.writer = writer
        self.parser = parser
        self.timeout = timeout
    }

    @concurrent
    func generate(
        _ request: SSHKeyGenerationRequest,
        passphrase: Passphrase,
        in directory: SSHDirectory
    ) async throws(SSHKeyGenerationError) -> SSHKeyPair {
        guard toolURL.path(percentEncoded: false).hasPrefix("/") else {
            throw .toolUnavailable(toolURL)
        }
        guard await reader.fileExists(at: toolURL) else {
            throw .toolUnavailable(toolURL)
        }
        // Reported, never created: creating the user's SSH directory behind their back is
        // not this app's decision to make.
        guard await reader.directoryExists(at: directory.url) else {
            throw .directoryMissing(directory.url)
        }

        let privateKeyURL = request.name.privateKeyURL(in: directory.url)
        let publicKeyURL = request.name.publicKeyURL(in: directory.url)

        // Probed *before* the launch so that cleanup can be limited to files this generator
        // actually produced. A file that was already there belongs to the user, and removing
        // it would be exactly the bystander deletion the rest of the design prevents.
        let preexisting = await existing(among: [privateKeyURL, publicKeyURL])

        let outcome = await Self.run(
            tool: toolURL,
            arguments: request.keygenArguments(in: directory.url),
            workingDirectory: directory.url,
            passphrase: passphrase,
            timeout: timeout
        )

        do {
            return try await accept(outcome, for: request, privateKeyURL: privateKeyURL, publicKeyURL: publicKeyURL)
        } catch {
            await discard([privateKeyURL, publicKeyURL], except: preexisting)
            throw error
        }
    }

    // MARK: - The acceptance gate

    /// Accepts the result only on evidence: a clean exit, both files present, and a public
    /// key whose parsed attributes are the ones that were asked for.
    private func accept(
        _ outcome: ToolOutcome,
        for request: SSHKeyGenerationRequest,
        privateKeyURL: URL,
        publicKeyURL: URL
    ) async throws(SSHKeyGenerationError) -> SSHKeyPair {
        switch outcome {
        case .timedOut:
            throw .timedOut
        case .launchFailed:
            throw .toolUnavailable(toolURL)
        case .exited(let status, let diagnostics) where status != 0:
            throw .toolFailed(status: status, detail: diagnostics)
        case .exited:
            break
        }

        guard await reader.fileExists(at: privateKeyURL) else {
            throw .outputMissing(privateKeyURL)
        }
        guard await reader.fileExists(at: publicKeyURL) else {
            throw .outputMissing(publicKeyURL)
        }

        guard let contents = try? await reader.contents(of: publicKeyURL) else {
            throw .outputUnreadable(publicKeyURL)
        }
        guard case .success(let publicKey) = parser.parse(contents) else {
            throw .outputUnreadable(publicKeyURL)
        }

        // Checking presence alone would still pass a key of the wrong type, which is the
        // whole reason this comparison exists.
        guard publicKey.algorithm.matches(request.type),
              publicKey.bitLength == request.type.expectedBitLength
        else {
            throw .outputMismatch(expected: request.type, actual: publicKey.algorithm)
        }

        // The pair is described by what is on disk, not by what was requested.
        return SSHKeyPair(
            location: SSHKeyPairLocation(
                name: request.name,
                publicKeyURL: publicKeyURL,
                privateKeyURL: privateKeyURL,
                certificateURL: nil
            ),
            publicKey: .success(publicKey)
        )
    }

    private func existing(among urls: [URL]) async -> Set<String> {
        var present: Set<String> = []
        for url in urls where await reader.fileExists(at: url) {
            present.insert(url.standardizedFileURL.path(percentEncoded: false))
        }
        return present
    }

    /// Removes the output this generator produced and then rejected, leaving anything that
    /// was already there untouched.
    ///
    /// Best effort: a removal that fails changes nothing about the failure already being
    /// reported, and reporting the cleanup instead of the cause would bury it.
    private func discard(_ urls: [URL], except preexisting: Set<String>) async {
        for url in urls
        where !preexisting.contains(url.standardizedFileURL.path(percentEncoded: false)) {
            try? await writer.remove(at: url)
        }
    }

    // MARK: - Running the tool

    private enum ToolOutcome: Sendable {
        case launchFailed
        case exited(status: Int32, diagnostics: String)
        case timedOut
    }

    /// Runs the tool to completion, or to the timeout, and returns what it did.
    ///
    /// Bridged onto a dispatch queue rather than written with `async` primitives. `Process`
    /// and `FileHandle` are blocking, callback-shaped APIs and `Process` is not `Sendable`;
    /// confining the whole of it to one closure on one queue keeps that fact in one place
    /// instead of spreading `nonisolated(unsafe)` captures across several tasks. The
    /// cooperative pool is not blocked, because this is not running on it.
    private static func run(
        tool: URL,
        arguments: [String],
        workingDirectory: URL,
        passphrase: Passphrase,
        timeout: Duration
    ) async -> ToolOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    returning: blockingRun(
                        tool: tool,
                        arguments: arguments,
                        workingDirectory: workingDirectory,
                        passphrase: passphrase,
                        timeout: timeout
                    )
                )
            }
        }
    }

    private static func blockingRun(
        tool: URL,
        arguments: [String],
        workingDirectory: URL,
        passphrase: Passphrase,
        timeout: Duration
    ) -> ToolOutcome {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        // Emptied rather than filtered. An inherited environment is a channel the passphrase
        // must never travel on, and `ssh-keygen` needs nothing from it: the target is an
        // absolute path supplied as an argument.
        process.environment = [:]

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return .launchFailed
        }

        // Both streams are drained concurrently with the wait. `ssh-keygen` writes its
        // prompts and its summary before exiting, and a full pipe would otherwise block the
        // tool while the app waited for it to finish.
        let drained = DispatchGroup()
        let collected = Collected()
        drain(output, into: collected, stream: .standardOutput, group: drained)
        drain(errors, into: collected, stream: .standardError, group: drained)

        write(passphrase, to: input)

        // The whole operation is bounded. A tool that neither finishes nor fails is the one
        // failure mode a subprocess can inflict on the app that the app cannot otherwise
        // recover from.
        let deadline = DispatchTime.now() + timeout.seconds
        if exited.wait(timeout: deadline) == .timedOut {
            process.terminate()
            // Give the signal a moment to land, then stop waiting regardless: the outcome is
            // already decided.
            _ = exited.wait(timeout: .now() + 2)
            _ = drained.wait(timeout: .now() + 2)
            return .timedOut
        }

        _ = drained.wait(timeout: .now() + 5)

        return .exited(
            status: process.terminationStatus,
            diagnostics: collected.diagnostics
        )
    }

    /// Writes the passphrase, then closes the stream.
    ///
    /// The same buffer twice, for the prompt and its confirmation. Closing afterwards means a
    /// prompt the app did not anticipate — the overwrite confirmation, say — reads end of
    /// file and the tool fails, rather than waiting forever on input that will not come.
    private static func write(_ passphrase: Passphrase, to input: Pipe) {
        let buffer = Data((passphrase.secret + "\n").utf8)

        // Two writes of a handful of bytes cannot fill a pipe buffer, so this cannot block.
        try? input.fileHandleForWriting.write(contentsOf: buffer)
        try? input.fileHandleForWriting.write(contentsOf: buffer)
        try? input.fileHandleForWriting.close()
    }

    private static func drain(
        _ pipe: Pipe,
        into collected: Collected,
        stream: Collected.Stream,
        group: DispatchGroup
    ) {
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            collected.append(data, to: stream)
        }
    }

    /// What the two streams produced, collected under a lock because they are drained on two
    /// queues at once.
    private final class Collected: @unchecked Sendable {
        enum Stream: Sendable {
            case standardOutput
            case standardError
        }

        private let lock = NSLock()
        private var standardOutput = Data()
        private var standardError = Data()

        func append(_ data: Data, to stream: Stream) {
            lock.withLock {
                switch stream {
                case .standardOutput: standardOutput.append(data)
                case .standardError: standardError.append(data)
                }
            }
        }

        /// The tool's own diagnostic text, preferring standard error and falling back to
        /// standard output.
        ///
        /// Safe to show the user: the passphrase arrives on standard input and `ssh-keygen`
        /// does not echo it.
        var diagnostics: String {
            let text = lock.withLock {
                standardError.isEmpty ? standardOutput : standardError
            }
            return String(decoding: text, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

nonisolated extension Duration {
    /// Seconds as a `Double`, for the dispatch waits above.
    fileprivate var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
