import Foundation

/// A reader that sees what an `InMemorySSHConfigWriter` has written, falling back to a fixed
/// in-memory reader for everything else.
///
/// It is what lets a model test assert the outcome a user would see — "the new host appears
/// after the reload" — rather than only that a write was requested.
nonisolated struct WriterBackedSSHDirectoryReader: SSHDirectoryReading {

    let base: InMemorySSHDirectoryReader
    let writer: InMemorySSHConfigWriter

    func directoryExists(at url: URL) async -> Bool {
        await base.directoryExists(at: url)
    }

    func fileExists(at url: URL) async -> Bool {
        if writer.contents(of: await writer.resolvedLocation(of: url)) != nil { return true }
        return await base.fileExists(at: url)
    }

    func entries(in url: URL) async throws(FileAccessError) -> [URL] {
        try await base.entries(in: url)
    }

    /// A failure the base reader was scripted with still wins, so an unreadable file stays
    /// unreadable; otherwise whatever the writer holds now is what a read sees.
    func contents(of url: URL) async throws(FileAccessError) -> Data {
        let written = writer.contents(of: await writer.resolvedLocation(of: url))
        do {
            let original = try await base.contents(of: url)
            return written ?? original
        } catch .directoryNotFound {
            guard let written else { throw .directoryNotFound(url) }
            return written
        }
    }
}
