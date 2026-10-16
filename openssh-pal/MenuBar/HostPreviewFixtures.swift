#if DEBUG
import Foundation

/// Models over fabricated files, for the host surfaces' previews only.
///
/// Previews need real models, and real models need ports. These conformers hold values and
/// touch nothing: there is no file system here, and nothing in a preview can write. Compiled
/// into debug builds only, and constructed nowhere but in a `#Preview`.
@MainActor
enum HostPreviewFixtures {

    static let directory = URL(filePath: "/preview/keys", directoryHint: .isDirectory)

    struct Models {
        let status: SSHDirectoryStatusModel
        let configuration: SSHConfigModel
        let keys: SSHKeyListModel
        let form: HostFormModel

        func load() async {
            await configuration.refresh()
            await keys.refresh()
        }
    }

    /// Models over a directory holding `config` (none when `nil`), any other `files`, and the
    /// named key pairs.
    static func models(config: String?, files: [String: String] = [:], keyNames: [String] = ["id_ed25519", "id_work"]) -> Models {
        var contents: [String: Data] = [:]
        if let config { contents["config"] = Data(config.utf8) }
        for (name, text) in files { contents[name] = Data(text.utf8) }
        for name in keyNames {
            contents[name] = Data()
            contents[name + ".pub"] = Data("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHG/eTv0q9SPBgITfzHoiFX9BXBTCO4InzbH19BagKve preview@host\n".utf8)
        }

        let reader = PreviewReader(directory: directory, files: contents)
        let status = SSHDirectoryStatusModel(
            resolver: SSHDirectoryResolver(reader: reader),
            launchEnvironment: LaunchEnvironment(
                arguments: [LaunchEnvironment.overrideArgument, directory.path(percentEncoded: false)],
                environmentVariables: [:]
            ),
            homeDirectory: URL(filePath: "/preview/home", directoryHint: .isDirectory),
            reader: reader
        )
        let configuration = SSHConfigModel(
            status: status,
            reader: reader,
            writer: PreviewConfigWriter(),
            homeDirectory: URL(filePath: "/preview/home", directoryHint: .isDirectory),
            userName: "preview"
        )
        let keys = SSHKeyListModel(
            status: status,
            reader: reader,
            writer: PreviewKeyWriter(),
            clipboard: PreviewClipboard(),
            hostReferences: configuration
        )
        return Models(status: status, configuration: configuration, keys: keys, form: HostFormModel(configuration: configuration, keys: keys))
    }

    static let sampleConfig = """
        Include config.d/*

        Host bastion
            HostName bastion.example.com
            User alice
            IdentityFile ~/keys/id_work

        Host web
            HostName 10.0.0.5
            Port 2222
            IdentityFile /preview/keys/id_work

        Host *.corp
            User corp-user

        Host db
            IdentityFile ~/keys/%h
        """
}

/// A read port over fabricated contents.
private nonisolated struct PreviewReader: SSHDirectoryReading {
    let directory: URL
    let files: [String: Data]

    func directoryExists(at url: URL) async -> Bool { url.standardizedFileURL == directory.standardizedFileURL }
    func fileExists(at url: URL) async -> Bool { files[url.lastPathComponent] != nil }

    func entries(in url: URL) async throws(FileAccessError) -> [URL] {
        guard url.standardizedFileURL == directory.standardizedFileURL else { throw .directoryNotFound(url) }
        return files.keys.map { directory.appending(path: $0) }
    }

    func contents(of url: URL) async throws(FileAccessError) -> Data {
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              let data = files[url.lastPathComponent]
        else { throw .directoryNotFound(url) }
        return data
    }
}

/// A write port that refuses everything, so a preview cannot write anywhere.
private nonisolated struct PreviewConfigWriter: SSHConfigWriting {
    func resolvedLocation(of url: URL) async -> URL { url }
    func backUpIfAbsent(_ file: URL, to backup: URL, within directory: SSHDirectory) async throws(SSHConfigWriteError) -> BackupOutcome {
        throw .failed(file)
    }
    func replace(_ file: URL, expecting expected: Data, with contents: Data, within directory: SSHDirectory) async throws(SSHConfigWriteError) {
        throw .failed(file)
    }
    func create(_ file: URL, with contents: Data, within directory: SSHDirectory) async throws(SSHConfigWriteError) {
        throw .failed(file)
    }
}

private nonisolated struct PreviewKeyWriter: SSHKeyWriting {
    func move(from source: URL, to destination: URL) async throws(SSHKeyWriteError) { throw .failed(source) }
    func remove(at url: URL) async throws(SSHKeyWriteError) { throw .failed(url) }
}

private nonisolated struct PreviewClipboard: ClipboardWriting {
    func write(_ text: String) async {}
}
#endif
