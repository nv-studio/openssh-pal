import Foundation

/// A scratch directory that exists only for the duration of one test.
///
/// Tests that need a real file system get one of these rather than a path under the
/// developer's home directory. `withOne(perform:)` is the only way to obtain one, so
/// removal cannot be forgotten, and the removal runs on the failure path too — a test that
/// throws still leaves nothing behind.
struct TemporaryDirectory {
    let url: URL

    /// Creates a scratch directory, passes it to `body`, and removes it unconditionally.
    static func withOne<T>(perform body: (TemporaryDirectory) async throws -> T) async throws -> T {
        let directory = try TemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.url) }
        return try await body(directory)
    }

    private init() throws {
        url = URL.temporaryDirectory.appending(
            path: "open-ssh-gui-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Writes a regular file directly inside the scratch directory.
    @discardableResult
    func file(named name: String, contents: Data = Data()) throws -> URL {
        let file = url.appending(path: name)
        try contents.write(to: file)
        return file
    }

    /// Creates a subdirectory directly inside the scratch directory.
    @discardableResult
    func subdirectory(named name: String) throws -> URL {
        let subdirectory = url.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        return subdirectory
    }
}
