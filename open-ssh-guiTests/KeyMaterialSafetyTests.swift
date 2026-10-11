import Foundation
import Testing

/// That using a GUI is not less safe than using the terminal: no private key byte is read, no
/// file leaves the device, and no passphrase is written, logged, argued or printed.
///
/// Most of these are asserted by behaviour. The two that are claims about *every* code path at
/// once are asserted against the sources, because there is no behaviour that demonstrates an
/// absence.
@MainActor
@Suite("Key material and passphrase safety")
struct KeyMaterialSafetyTests {

    nonisolated private static let secret = "correct horse battery staple"
    nonisolated private static let home = URL(filePath: "/fabricated/home", directoryHint: .isDirectory)
    nonisolated private static let keys = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)
    nonisolated private static let ed25519Line = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHG/eTv0q9SPBgITfzHoiFX9BXBTCO4InzbH19BagKve user@host"
    nonisolated private static let privateKeyMaterial = "-----BEGIN OPENSSH PRIVATE KEY-----\nSECRET BYTES\n"

    nonisolated private static func override(_ url: URL) -> LaunchEnvironment {
        LaunchEnvironment(
            arguments: [LaunchEnvironment.overrideArgument, url.path(percentEncoded: false)],
            environmentVariables: [:]
        )
    }

    // MARK: - 10.1 / 10.2 no private key is ever read

    @Test("Across every operation the feature performs, no private key file's contents are read")
    func noPrivateKeyIsEverRead() async throws {
        let entries = ["work_key", "work_key.pub", "work_key-cert.pub", "other", "other.pub"]
        let inMemory = InMemorySSHDirectoryReader(
            directories: [Self.keys: entries.map { Self.keys.appending(path: $0) }],
            files: Dictionary(
                uniqueKeysWithValues: entries.map { name in
                    (
                        Self.keys.appending(path: name),
                        Data((name.hasSuffix(".pub") ? Self.ed25519Line : Self.privateKeyMaterial).utf8)
                    )
                }
            )
        )
        let reader = AuditingSSHDirectoryReader(wrapping: inMemory)
        let writer = InMemorySSHKeyWriter()
        let clipboard = RecordingClipboardWriter()

        let model = SSHKeyListModel(
            status: SSHDirectoryStatusModel(
                resolver: SSHDirectoryResolver(reader: reader),
                launchEnvironment: Self.override(Self.keys),
                homeDirectory: Self.home,
                reader: reader
            ),
            reader: reader,
            writer: writer,
            clipboard: clipboard
        )

        // Everything the feature can be asked to do, in one pass.
        await model.refresh()
        let pair = try #require(model.state.pairs.first { $0.displayName == "work_key" })
        await model.copyPublicKey(of: pair)
        model.beginRename(of: pair)
        model.renameProposal = "renamed_key"
        await model.confirmRename()
        await model.refresh()
        let other = try #require(model.state.pairs.first { $0.displayName == "other" })
        await model.delete(other)

        #expect(!reader.contentsRead.isEmpty, "the audit would be vacuous if nothing was read")

        for url in reader.contentsRead {
            #expect(
                url.lastPathComponent.hasSuffix(".pub"),
                "\(url.lastPathComponent) is not a public key, and its contents were read"
            )
        }

        // And nothing that was read reached the clipboard except a public key line.
        let privateMarker = "PRIVATE KEY"
        for written in clipboard.writes {
            #expect(written.range(of: privateMarker) == nil)
        }
    }

    @Test("A parse reads only the bytes it is handed, so it cannot reach a private key at all")
    func theParserHasNoWayToReachAFile() {
        // The signature is the guarantee: `Data` in, attributes out. There is no URL, no
        // reader and no path for it to follow.
        let parsed = SSHPublicKeyParser().parse(Data(Self.ed25519Line.utf8))

        #expect((try? parsed.get()) != nil)
    }

    @Test("The clipboard port takes text, so there is no call that could copy a private key")
    func theClipboardPortCannotReachAFile() async {
        let clipboard = RecordingClipboardWriter()

        // `write(_ text:)` is the whole port. A path cannot be passed to it.
        await clipboard.write(Self.ed25519Line)

        #expect(clipboard.writes == [Self.ed25519Line])
    }

    // MARK: - 10.3 nothing leaves the device

    @Test("No application source references any networking interface")
    func nothingCanTransmitAFile() throws {
        // An absence cannot be demonstrated by behaviour, so it is checked against the
        // sources. `product.md` commits that no `~/.ssh` content leaves the device; this is
        // what makes that commitment fail loudly if someone adds a client.
        let networking = [
            "URLSession", "NSURLConnection", "URLRequest", "CFNetwork", "Network.framework",
            "import Network", "NWConnection", "Socket", "socket(",
        ]

        for source in try ProjectSources.application() {
            for symbol in networking {
                #expect(
                    !source.text.contains(symbol),
                    "\(source.relativePath) references \(symbol): \(source.lines(containing: symbol))"
                )
            }
        }
    }

    @Test("FileManager appears only in the one directory permitted to touch the file system")
    func fileManagerIsConfinedToItsLayer() throws {
        for source in try ProjectSources.application() {
            guard source.text.contains("FileManager") else { continue }
            #expect(
                source.isIn("open-ssh-gui/FileAccess") || source.relativePath == "open-ssh-gui/OpenSSHGUIApp.swift",
                "\(source.relativePath) uses FileManager outside FileAccess/"
            )
        }
    }

    // MARK: - 10.5 the passphrase is not observable from a process listing

    @Test("The passphrase reaches ssh-keygen on standard input, and is in neither argv nor the environment")
    func passphraseIsNotInArgvOrTheEnvironment() async throws {
        // Against a stub executable, never `ssh-keygen`. The stub records exactly what a
        // process listing would have shown.
        try await TemporaryDirectory.withOne { scratch in
            let keysDirectory = try scratch.subdirectory(named: "keys")
            let recordings = try scratch.subdirectory(named: "recordings")
            let bin = try scratch.subdirectory(named: "bin")
            let tool = bin.appending(path: "keygen-stub")

            let script = """
                #!/bin/sh
                /bin/cat > '\(recordings.path(percentEncoded: false))/stdin'
                printf '%s\\n' "$@" > '\(recordings.path(percentEncoded: false))/argv'
                /usr/bin/env > '\(recordings.path(percentEncoded: false))/env'
                printf '%s\\n' 'PRIVATE' > '\(keysDirectory.path(percentEncoded: false))/work_key'
                printf '%s\\n' '\(Self.ed25519Line)' > '\(keysDirectory.path(percentEncoded: false))/work_key.pub'
                exit 0
                """
            try Data(script.utf8).write(to: tool)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: tool.path(percentEncoded: false)
            )

            let generator = ProcessSSHKeyGenerator(
                toolURL: tool,
                reader: FileSystemSSHDirectoryReader(),
                writer: FileSystemSSHKeyWriter(),
                parser: SSHPublicKeyParser(),
                timeout: .seconds(10)
            )

            _ = try await generator.generate(
                SSHKeyGenerationRequest(
                    name: try #require(SSHKeyName.discovered("work_key")),
                    type: .ed25519,
                    comment: "user@host"
                ),
                passphrase: Passphrase(Self.secret),
                in: SSHDirectory(url: keysDirectory)
            )

            func recorded(_ name: String) throws -> String {
                String(decoding: try Data(contentsOf: recordings.appending(path: name)), as: UTF8.self)
            }

            #expect(try recorded("stdin").contains(Self.secret), "the audit would be vacuous otherwise")
            #expect(!(try recorded("argv").contains(Self.secret)))
            #expect(!(try recorded("env").contains(Self.secret)))
        }
    }

    @Test("No argument list any request can produce carries a secret or the flags that would")
    func noRequestCanCarryASecret() throws {
        let name = try #require(SSHKeyName.discovered("work_key"))

        for type in SSHKeyType.allCases {
            let arguments = SSHKeyGenerationRequest(name: name, type: type, comment: "user@host")
                .keygenArguments(in: Self.keys)

            #expect(!arguments.contains("-N"), "-N would put the passphrase in the argument list")
            #expect(!arguments.contains("-P"))
            for argument in arguments {
                #expect(!argument.contains(Self.secret))
            }
        }
    }

    @Test("No application source spells the flags that would put a passphrase in a process listing")
    func noSourceUsesThePassphraseFlags() throws {
        for source in try ProjectSources.application() {
            #expect(!source.text.contains("\"-N\""), "\(source.relativePath) spells -N")
            #expect(!source.text.contains("\"-P\""), "\(source.relativePath) spells -P")
        }
    }

    // MARK: - 10.4 nothing is written down

    @Test("A generation writes no file containing the passphrase")
    func noFileEverHoldsThePassphrase() async throws {
        try await TemporaryDirectory.withOne { scratch in
            let keysDirectory = try scratch.subdirectory(named: "keys")
            let bin = try scratch.subdirectory(named: "bin")
            let tool = bin.appending(path: "keygen-stub")

            // Discards standard input rather than recording it, so anything found below came
            // from the app rather than from the stub.
            let script = """
                #!/bin/sh
                /bin/cat > /dev/null
                printf '%s\\n' 'PRIVATE' > '\(keysDirectory.path(percentEncoded: false))/work_key'
                printf '%s\\n' '\(Self.ed25519Line)' > '\(keysDirectory.path(percentEncoded: false))/work_key.pub'
                exit 0
                """
            try Data(script.utf8).write(to: tool)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: tool.path(percentEncoded: false)
            )

            let form = NewKeyFormModel(
                generator: ProcessSSHKeyGenerator(
                    toolURL: tool,
                    reader: FileSystemSSHDirectoryReader(),
                    writer: FileSystemSSHKeyWriter(),
                    parser: SSHPublicKeyParser(),
                    timeout: .seconds(10)
                ),
                defaultComment: "user@host"
            )
            form.begin(in: SSHDirectory(url: keysDirectory), existing: [])
            form.name = "work_key"
            form.passphraseText = Self.secret
            form.confirmationText = Self.secret

            form.submit()
            await form.waitForGeneration()

            #expect(form.completion?.createdPair != nil)

            for file in try FileManager.default.contentsOfDirectory(at: scratch.url, includingPropertiesForKeys: nil) {
                try Self.expectNoSecret(under: file)
            }
        }
    }

    @Test("The form retains no passphrase once it is done, on any exit path")
    func theFormRetainsNoPassphrase() async {
        for finish in ["cancel", "succeed", "fail"] {
            let outcome: Result<SSHKeyPair, SSHKeyGenerationError> = finish == "fail"
                ? .failure(.timedOut)
                : .success(
                    SSHKeyPair(
                        location: SSHKeyPairLocation(
                            name: SSHKeyName.discovered("work_key")!,
                            publicKeyURL: Self.keys.appending(path: "work_key.pub"),
                            privateKeyURL: Self.keys.appending(path: "work_key"),
                            certificateURL: nil
                        ),
                        publicKey: .failure(.empty)
                    )
                )

            let form = NewKeyFormModel(
                generator: StubSSHKeyGenerator(outcome: outcome),
                defaultComment: "user@host"
            )
            form.begin(in: SSHDirectory(url: Self.keys), existing: [])
            form.name = "work_key"
            form.passphraseText = Self.secret
            form.confirmationText = Self.secret

            if finish == "cancel" {
                form.cancel()
            } else {
                form.submit()
                await form.waitForGeneration()
            }

            #expect(form.passphrase == .none, "a passphrase survived \(finish)")
            #expect(form.passphraseText.isEmpty)
            #expect(form.confirmationText.isEmpty)
            #expect(!form.isPassphraseRevealed)
        }
    }

    // MARK: - 10.8 no reason anywhere carries a secret

    @Test("No error reason in the feature's vocabularies carries a secret")
    func noReasonCarriesASecret() {
        let secretish: [String] = [Self.secret, Self.privateKeyMaterial, "PRIVATE KEY"]

        var reasons: [String] = [
            SSHKeyNameError.empty.reason,
            SSHKeyNameError.notAPlainFileName(Self.secret).reason,
            SSHKeyNameError.endsInPublicKeyExtension("k.pub").reason,
            SSHKeyNameError.reservedByOpenSSH("config").reason,
            SSHKeyNameError.wouldReplace(Self.keys.appending(path: "work_key")).reason,
        ]

        reasons += [
            SSHKeyWriteError.destinationExists(Self.keys.appending(path: "work_key")),
            .notFound(Self.keys.appending(path: "work_key")),
            .accessDenied(Self.keys.appending(path: "work_key")),
            .failed(Self.keys.appending(path: "work_key")),
        ].map(\.reason)

        reasons += [
            SSHKeyGenerationError.toolUnavailable(URL(filePath: "/fabricated/bin/ssh-keygen")),
            .directoryMissing(Self.keys),
            .toolFailed(status: 1, detail: "unknown key type"),
            .outputMissing(Self.keys.appending(path: "work_key")),
            .outputUnreadable(Self.keys.appending(path: "work_key.pub")),
            .outputMismatch(expected: .ed25519, actual: .rsa),
            .timedOut,
        ].map(\.reason)

        reasons += [
            KeyListNotice.failed(reason: "something went wrong"),
            .leftIncomplete(reason: "something went wrong"),
            .copied(SSHKeyName.discovered("work_key")!),
            .generated(SSHKeyName.discovered("work_key")!),
        ].map(\.message)

        for reason in reasons {
            for forbidden in secretish {
                #expect(!reason.contains(forbidden), "a reason carried \(forbidden): \(reason)")
            }
        }
    }

    @Test("A passphrase cannot be interpolated into a message, however it is described")
    func aPassphraseCannotBeDescribed() {
        let passphrase = Passphrase(Self.secret)

        let descriptions = [
            "\(passphrase)",
            String(describing: passphrase),
            String(reflecting: passphrase),
            passphrase.description,
            passphrase.debugDescription,
            "failed with \(passphrase) supplied",
        ]

        for description in descriptions {
            #expect(!description.contains(Self.secret))
            #expect(description.contains(Passphrase.redactedMarker))
        }
    }

    /// Fails if `url`, or anything under it, holds the secret.
    nonisolated private static func expectNoSecret(under url: URL) throws {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)

        if isDirectory.boolValue {
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                try expectNoSecret(under: child)
            }
            return
        }

        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(!text.contains(secret), "\(url.lastPathComponent) holds the passphrase")
    }
}
