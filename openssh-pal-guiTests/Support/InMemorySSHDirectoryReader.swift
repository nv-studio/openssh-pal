import Foundation

/// A `SSHDirectoryReading` conformer backed entirely by fabricated values.
///
/// Modelled as an immutable value so parallel Swift Testing suites can share an instance
/// without coordination. Nothing in it touches the file system, which is what lets the
/// suite exercise every resolution and status rule without going near a real SSH
/// directory.
nonisolated struct InMemorySSHDirectoryReader: SSHDirectoryReading {

    /// Fabricated directories and the entries each one lists.
    private let directories: [String: [URL]]

    /// Fabricated regular files and their contents.
    private let files: [String: Data]

    /// Paths that should fail, and the failure each one produces.
    private let failures: [String: FileAccessError]

    init(
        directories: [URL: [URL]] = [:],
        files: [URL: Data] = [:],
        failures: [URL: FileAccessError] = [:]
    ) {
        self.directories = directories.keyedByNormalizedPath()
        self.files = files.keyedByNormalizedPath()
        self.failures = failures.keyedByNormalizedPath()
    }

    func directoryExists(at url: URL) async -> Bool {
        directories[url.normalizedPath] != nil
    }

    func fileExists(at url: URL) async -> Bool {
        let path = url.normalizedPath
        return directories[path] != nil || files[path] != nil
    }

    func entries(in url: URL) async throws(FileAccessError) -> [URL] {
        let path = url.normalizedPath
        if let failure = failures[path] { throw failure }
        guard let entries = directories[path] else { throw .directoryNotFound(url) }
        return entries
    }

    func contents(of url: URL) async throws(FileAccessError) -> Data {
        let path = url.normalizedPath
        if let failure = failures[path] { throw failure }
        guard let contents = files[path] else { throw .directoryNotFound(url) }
        return contents
    }
}

nonisolated extension URL {
    /// A comparison key that treats `/a/b` and `/a/b/` as the same location, so a caller
    /// need not match the exact spelling a fixture was written with.
    fileprivate var normalizedPath: String {
        let path = standardizedFileURL.path(percentEncoded: false)
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
}

nonisolated extension Dictionary where Key == URL {
    fileprivate func keyedByNormalizedPath() -> [String: Value] {
        Dictionary<String, Value>(
            map { ($0.key.normalizedPath, $0.value) },
            uniquingKeysWith: { _, latest in latest }
        )
    }
}
