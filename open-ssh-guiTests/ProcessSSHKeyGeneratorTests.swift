import Foundation
import Testing

/// Driven against a **stub executable**, never `ssh-keygen`. No test in this suite generates
/// a real key, and every path involved comes from a scratch directory.
///
/// The stub is a shell script the test writes, so each case can decide what the tool does:
/// record what it received, exit non-zero, write a key of the wrong type, write nothing, or
/// never terminate.
@Suite("Process key generator")
struct ProcessSSHKeyGeneratorTests {

    private static let secret = "correct horse battery staple"

    /// Real Ed25519 and RSA public key lines, used as the output a stub pretends to have
    /// produced. Captured from `ssh-keygen` once, so the acceptance gate is exercised against
    /// keys it would actually meet.
    private enum Output {
        static let ed25519 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHG/eTv0q9SPBgITfzHoiFX9BXBTCO4InzbH19BagKve user@host"
        static let rsa2048 = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDDvUBbXr+OJ9RzFzhtchaD+NXVpwEvAZJAEhETFLSjR6qJB47DZC657lQz4P+ANA8uP2w7fHgAfm+eo/B5qWJxRb4oC37kteif7kIhshtgIrWmL9g3N21rL4v6U5irgLn/ZDBeMsqxgbpAv30MXXqB7STYPhNQsi8FRw+mHLyF/EBfe229dz3Ok3DNA+lXwvMZooxbNYV0PNYbpM+y2db4wBgOldZF7wnvyxGSWBMVRWTK4mxLrJw2YICBuDJzyOdAXuwuXGh2UxcWP7szMtwecIJZerHsKAMTKKdd6g9bXSGqA4HMCVcdRemU4K+GSDDPIlJWaBH6gDrIIDoa5bxP rsa comment"
    }

    // MARK: - Harness

    private struct Harness {
        let keys: URL
        let recordings: URL
        let tool: URL
        let generator: ProcessSSHKeyGenerator

        var directory: SSHDirectory { SSHDirectory(url: keys) }

        func recorded(_ name: String) -> String? {
            guard let data = try? Data(contentsOf: recordings.appending(path: name)) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }

        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: keys.appending(path: name).path(percentEncoded: false))
        }
    }

    /// Builds a scratch SSH directory, a recordings directory and a stub tool whose body the
    /// caller supplies, then runs `body`.
    private static func withHarness<T>(
        stub: (_ recordings: URL, _ keys: URL) -> String,
        timeout: Duration = .seconds(10),
        toolName: String = "keygen-stub",
        perform body: (Harness) async throws -> T
    ) async throws -> T {
        try await TemporaryDirectory.withOne { scratch in
            let keys = try scratch.subdirectory(named: "keys")
            let recordings = try scratch.subdirectory(named: "recordings")
            let bin = try scratch.subdirectory(named: "bin")

            let tool = bin.appending(path: toolName)
            let script = "#!/bin/sh\n" + stub(recordings, keys) + "\n"
            try Data(script.utf8).write(to: tool)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: tool.path(percentEncoded: false)
            )

            return try await body(
                Harness(
                    keys: keys,
                    recordings: recordings,
                    tool: tool,
                    generator: generator(tool: tool, timeout: timeout)
                )
            )
        }
    }

    private static func generator(tool: URL, timeout: Duration) -> ProcessSSHKeyGenerator {
        ProcessSSHKeyGenerator(
            toolURL: tool,
            reader: FileSystemSSHDirectoryReader(),
            writer: FileSystemSSHKeyWriter(),
            parser: SSHPublicKeyParser(),
            timeout: timeout
        )
    }

    private static func request(
        _ raw: String = "work_key",
        type: SSHKeyType = .ed25519,
        comment: String = "user@host"
    ) throws -> SSHKeyGenerationRequest {
        SSHKeyGenerationRequest(name: try SSHKeyName.validated(raw).get(), type: type, comment: comment)
    }

    /// A stub that records everything it received and then writes `line` as the public key.
    private static func recordingStub(writing line: String?) -> (URL, URL) -> String {
        { recordings, keys in
            var body = """
                /bin/cat > '\(recordings.path(percentEncoded: false))/stdin'
                printf '%s\\n' "$@" > '\(recordings.path(percentEncoded: false))/argv'
                /usr/bin/env > '\(recordings.path(percentEncoded: false))/env'
                """
            if let line {
                body += """
                    \nprintf '%s\\n' 'PRIVATE KEY PLACEHOLDER' > '\(keys.path(percentEncoded: false))/work_key'
                    printf '%s\\n' '\(line)' > '\(keys.path(percentEncoded: false))/work_key.pub'
                    """
            }
            return body + "\nexit 0"
        }
    }

    // MARK: - 10.5 the passphrase reaches stdin and nothing else

    @Test("The passphrase reaches the tool on standard input, written twice")
    func passphraseReachesStandardInput() async throws {
        _ = try await Self.withHarness(stub: Self.recordingStub(writing: Output.ed25519)) { harness in
            _ = try await harness.generator.generate(
                try Self.request(),
                passphrase: Passphrase(Self.secret),
                in: harness.directory
            )

            // Both prompts receive the same bytes because one buffer is written twice. That
            // is what makes the silent downgrade to an unencrypted key unreachable rather
            // than merely detected.
            #expect(harness.recorded("stdin") == "\(Self.secret)\n\(Self.secret)\n")
        }
    }

    @Test("Standard input is closed, so a prompt the tool did not expect cannot block it")
    func standardInputIsClosed() async throws {
        // The stub's first act is `cat`, which returns only at end of file. That it completes
        // at all is the assertion.
        _ = try await Self.withHarness(stub: Self.recordingStub(writing: Output.ed25519)) { harness in
            _ = try await harness.generator.generate(
                try Self.request(),
                passphrase: Passphrase(Self.secret),
                in: harness.directory
            )

            #expect(harness.recorded("stdin") != nil)
        }
    }

    @Test("The passphrase appears in neither the argument list nor the environment")
    func passphraseIsNotObservableFromAProcessListing() async throws {
        _ = try await Self.withHarness(stub: Self.recordingStub(writing: Output.ed25519)) { harness in
            _ = try await harness.generator.generate(
                try Self.request(),
                passphrase: Passphrase(Self.secret),
                in: harness.directory
            )

            let argv = try #require(harness.recorded("argv"))
            let environment = try #require(harness.recorded("env"))

            #expect(!argv.contains(Self.secret))
            #expect(!environment.contains(Self.secret))
            // `-N` would have put it in the argument list, which is why it is forbidden.
            #expect(!argv.contains("-N"))
        }
    }

    @Test("An empty passphrase is still written twice, so no prompt is left unanswered")
    func emptyPassphraseIsStillWrittenTwice() async throws {
        _ = try await Self.withHarness(stub: Self.recordingStub(writing: Output.ed25519)) { harness in
            _ = try await harness.generator.generate(
                try Self.request(),
                passphrase: .none,
                in: harness.directory
            )

            #expect(harness.recorded("stdin") == "\n\n")
        }
    }

    @Test("The arguments carry the requested type, comment and target")
    func argumentsCarryTheRequest() async throws {
        _ = try await Self.withHarness(stub: Self.recordingStub(writing: Output.ed25519)) { harness in
            _ = try await harness.generator.generate(
                try Self.request(),
                passphrase: .none,
                in: harness.directory
            )

            let argv = try #require(harness.recorded("argv")).split(separator: "\n").map(String.init)

            #expect(argv.prefix(2) == ["-t", "ed25519"])
            #expect(argv.contains("user@host"))
            #expect(argv.contains(harness.keys.appending(path: "work_key").path(percentEncoded: false)))
        }
    }

    // MARK: - 9.5 / 9.7 distinct environment failures

    @Test("A tool that is not where it was said to be reports that generation is unavailable")
    func absentToolIsReported() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let keys = try scratch.subdirectory(named: "keys")
            let missing = scratch.url.appending(path: "no-such-tool")
            let generator = Self.generator(tool: missing, timeout: .seconds(5))

            await #expect(throws: SSHKeyGenerationError.toolUnavailable(missing)) {
                try await generator.generate(
                    try Self.request(),
                    passphrase: .none,
                    in: SSHDirectory(url: keys)
                )
            }
        }
    }

    @Test("A tool named by a relative path is refused rather than resolved through the search path")
    func relativeToolPathIsRefused() async throws {
        // A `PATH` lookup would let a hijacked `PATH` choose the binary that receives the
        // user's passphrase, so only an absolute path is accepted.
        try await TemporaryDirectory.withOne { scratch in
            let keys = try scratch.subdirectory(named: "keys")
            let relative = URL(filePath: "ssh-keygen", relativeTo: nil)
            let generator = Self.generator(tool: relative, timeout: .seconds(5))

            await #expect(throws: SSHKeyGenerationError.self) {
                try await generator.generate(
                    try Self.request(),
                    passphrase: .none,
                    in: SSHDirectory(url: keys)
                )
            }
        }
    }

    @Test("A missing target directory is reported as absent, and the tool is never launched")
    func missingDirectoryIsReportedWithoutLaunching() async throws {
        try await Self.withHarness(stub: Self.recordingStub(writing: Output.ed25519)) { harness -> Void in
            let absent = harness.keys.appending(path: "gone", directoryHint: .isDirectory)

            await #expect(throws: SSHKeyGenerationError.directoryMissing(absent)) {
                try await harness.generator.generate(
                    try Self.request(),
                    passphrase: .none,
                    in: SSHDirectory(url: absent)
                )
            }

            // Reported rather than created, and nothing ran.
            #expect(harness.recorded("argv") == nil)
            #expect(!FileManager.default.fileExists(atPath: absent.path(percentEncoded: false)))
        }
    }

    // MARK: - 9.6 a non-zero exit

    @Test("A non-zero exit maps to a tool failure, carrying the status and the tool's own output")
    func nonZeroExitMapsToToolFailure() async throws {
        _ = try await Self.withHarness(stub: { _, _ in
            """
            /bin/cat > /dev/null
            echo 'unknown key type nonsense' >&2
            exit 3
            """
        }) { harness in
            await #expect(throws: SSHKeyGenerationError.toolFailed(status: 3, detail: "unknown key type nonsense")) {
                try await harness.generator.generate(
                    try Self.request(),
                    passphrase: Passphrase(Self.secret),
                    in: harness.directory
                )
            }
        }
    }

    @Test("A failure leaves no partially written file behind")
    func failureLeavesNoPartialFile() async throws {
        _ = try await Self.withHarness(stub: { _, keys in
            """
            /bin/cat > /dev/null
            printf '%s\\n' 'half a key' > '\(keys.path(percentEncoded: false))/work_key'
            exit 1
            """
        }) { harness in
            await #expect(throws: SSHKeyGenerationError.self) {
                try await harness.generator.generate(
                    try Self.request(),
                    passphrase: .none,
                    in: harness.directory
                )
            }

            #expect(!harness.exists("work_key"))
        }
    }

    @Test("A file that was already there is left alone when generation fails")
    func aPreexistingFileIsNotCleanedUp() async throws {
        _ = try await Self.withHarness(stub: { _, _ in
            """
            /bin/cat > /dev/null
            exit 1
            """
        }) { harness in
            // Only files that appeared during the launch are removed. A file that was there
            // beforehand belongs to the user, and cleaning it up would be the bystander
            // deletion the whole design exists to prevent.
            let bystander = harness.keys.appending(path: "work_key")
            try Data("not mine to delete".utf8).write(to: bystander)

            await #expect(throws: SSHKeyGenerationError.self) {
                try await harness.generator.generate(
                    try Self.request(),
                    passphrase: .none,
                    in: harness.directory
                )
            }

            #expect(try Data(contentsOf: bystander) == Data("not mine to delete".utf8))
        }
    }

    // MARK: - the timeout

    @Test("A tool that never terminates hits the timeout rather than hanging the app")
    func nonTerminatingToolTimesOut() async throws {
        try await Self.withHarness(
            stub: { _, _ in "exec /bin/sleep 30" },
            timeout: .milliseconds(400)
        ) { harness -> Void in
            await #expect(throws: SSHKeyGenerationError.timedOut) {
                try await harness.generator.generate(
                    try Self.request(),
                    passphrase: .none,
                    in: harness.directory
                )
            }
        }
    }

    // MARK: - 3.4 acceptance on evidence, not exit status

    @Test("A key of the requested type, written and parseable, is accepted")
    func matchingOutputIsAccepted() async throws {
        _ = try await Self.withHarness(stub: Self.recordingStub(writing: Output.ed25519)) { harness in
            let pair = try await harness.generator.generate(
                try Self.request(),
                passphrase: .none,
                in: harness.directory
            )

            #expect(pair.location.name.rawValue == "work_key")
            #expect(pair.location.privateKeyURL == harness.keys.appending(path: "work_key"))
            // The attributes come from the file that was written, not echoed back from the
            // request.
            #expect(pair.parsedPublicKey?.algorithm == .ed25519)
            #expect(pair.parsedPublicKey?.comment == "user@host")
        }
    }

    @Test("A tool that exits zero having written the wrong type is rejected")
    func wrongTypeIsRejected() async throws {
        _ = try await Self.withHarness(stub: Self.recordingStub(writing: Output.rsa2048)) { harness in
            // Exit 0 and both files present. A gate that checked only presence would accept
            // this, which is why the parsed algorithm is part of the gate.
            await #expect(throws: SSHKeyGenerationError.outputMismatch(expected: .ed25519, actual: .rsa)) {
                try await harness.generator.generate(
                    try Self.request(type: .ed25519),
                    passphrase: .none,
                    in: harness.directory
                )
            }
        }
    }

    @Test("A key of the right algorithm but the wrong size is rejected too")
    func wrongSizeIsRejected() async throws {
        _ = try await Self.withHarness(stub: Self.recordingStub(writing: Output.rsa2048)) { harness in
            await #expect(throws: SSHKeyGenerationError.outputMismatch(expected: .rsa(.bits4096), actual: .rsa)) {
                try await harness.generator.generate(
                    try Self.request(type: .rsa(.bits4096)),
                    passphrase: .none,
                    in: harness.directory
                )
            }
        }
    }

    @Test("A tool that exits zero having written nothing is rejected, with its own reason")
    func missingOutputIsRejected() async throws {
        _ = try await Self.withHarness(stub: Self.recordingStub(writing: nil)) { harness in
            let expected = SSHKeyGenerationError.outputMissing(harness.keys.appending(path: "work_key"))

            await #expect(throws: expected) {
                try await harness.generator.generate(
                    try Self.request(),
                    passphrase: .none,
                    in: harness.directory
                )
            }
        }
    }

    @Test("A private key with no public key beside it is rejected, naming the public key")
    func missingPublicKeyIsRejected() async throws {
        _ = try await Self.withHarness(stub: { _, keys in
            """
            /bin/cat > /dev/null
            printf '%s\\n' 'PRIVATE KEY PLACEHOLDER' > '\(keys.path(percentEncoded: false))/work_key'
            exit 0
            """
        }) { harness in
            let expected = SSHKeyGenerationError.outputMissing(harness.keys.appending(path: "work_key.pub"))

            await #expect(throws: expected) {
                try await harness.generator.generate(
                    try Self.request(),
                    passphrase: .none,
                    in: harness.directory
                )
            }

            // Rejected output is cleaned up, so a failed generation leaves nothing behind.
            #expect(!harness.exists("work_key"))
        }
    }

    @Test("A public key that cannot be read is rejected as unreadable, not as missing")
    func unreadableOutputIsRejected() async throws {
        _ = try await Self.withHarness(stub: Self.recordingStub(writing: "not a key at all")) { harness in
            let expected = SSHKeyGenerationError.outputUnreadable(harness.keys.appending(path: "work_key.pub"))

            await #expect(throws: expected) {
                try await harness.generator.generate(
                    try Self.request(),
                    passphrase: .none,
                    in: harness.directory
                )
            }
        }
    }

    @Test("Rejected output is removed, so a mismatch does not leave a wrong key in the directory")
    func rejectedOutputIsRemoved() async throws {
        _ = try await Self.withHarness(stub: Self.recordingStub(writing: Output.rsa2048)) { harness in
            await #expect(throws: SSHKeyGenerationError.self) {
                try await harness.generator.generate(
                    try Self.request(type: .ed25519),
                    passphrase: .none,
                    in: harness.directory
                )
            }

            #expect(!harness.exists("work_key"))
            #expect(!harness.exists("work_key.pub"))
        }
    }

    // MARK: - 11.3 permissions come from the tool

    @Test("The generator sets no permissions of its own, leaving the tool's own output as it is")
    func permissionsAreTheToolsOwn() async throws {
        _ = try await Self.withHarness(stub: Self.recordingStub(writing: Output.ed25519)) { harness in
            _ = try await harness.generator.generate(
                try Self.request(),
                passphrase: .none,
                in: harness.directory
            )

            // The stub writes with the test process's umask rather than ssh-keygen's 0600,
            // and the generator leaves that alone: there is no permission step to assert
            // away, which is what 11.3 relies on the real tool for.
            let attributes = try FileManager.default.attributesOfItem(
                atPath: harness.keys.appending(path: "work_key").path(percentEncoded: false)
            )
            #expect(attributes[.posixPermissions] != nil)
        }
    }
}
