import Foundation

/// The project's own source files, for the handful of guarantees that are about what the code
/// *does not* contain.
///
/// Most guarantees in this suite are asserted by behaviour, which is always better. A few —
/// "nothing transmits a file off the device", "`FileManager` appears in one directory only" —
/// are claims about every code path at once, and the only mechanical way to check those is to
/// read the sources. Doing it in a test means the claim fails when someone breaks it rather
/// than when a reviewer happens to notice.
///
/// The project is located from this file's own compile-time path, so nothing here names a
/// directory on any particular machine.
nonisolated enum ProjectSources {

    /// The application's source files.
    static func application() throws -> [Source] {
        try sources(in: root().appending(path: "open-ssh-gui", directoryHint: .isDirectory))
    }

    /// The test target's source files.
    static func tests() throws -> [Source] {
        try sources(in: root().appending(path: "open-ssh-guiTests", directoryHint: .isDirectory))
    }

    struct Source {
        let url: URL
        let text: String

        /// The path relative to the project root, which is what a failure should name.
        let relativePath: String

        /// Whether this file lives in the named source directory.
        func isIn(_ directory: String) -> Bool {
            relativePath.hasPrefix(directory + "/")
        }

        /// The lines mentioning `needle`, for a failure message that points at the problem.
        func lines(containing needle: String) -> [String] {
            text
                .split(whereSeparator: \.isNewline)
                .filter { $0.contains(needle) }
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    /// The project root, derived from this file's location rather than from any environment.
    private static func root() -> URL {
        URL(filePath: #filePath)            // .../open-ssh-guiTests/Support/ProjectSources.swift
            .deletingLastPathComponent()    // .../open-ssh-guiTests/Support
            .deletingLastPathComponent()    // .../open-ssh-guiTests
            .deletingLastPathComponent()    // the project root
    }

    private static func sources(in directory: URL) throws -> [Source] {
        let rootPath = root().path(percentEncoded: false)
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        )

        var sources: [Source] = []

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            let path = url.path(percentEncoded: false)
            sources.append(
                Source(
                    url: url,
                    text: text,
                    relativePath: String(path.dropFirst(rootPath.count))
                )
            )
        }

        return sources
    }
}
