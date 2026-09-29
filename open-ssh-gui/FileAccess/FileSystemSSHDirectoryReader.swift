import Foundation

/// The production `SSHDirectoryReading` conformer, backed by `FileManager`.
///
/// This is the only type in the app permitted to touch the file system. It reads directly,
/// with no security-scoped bookmark and no open panel, which is what disabling the App
/// Sandbox buys.
///
/// Both isolation annotations are load-bearing, and neither is redundant.
///
/// `nonisolated` on the type undoes `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a
/// caller that is not on the main actor can construct the adapter and read its stored
/// properties.
///
/// `@concurrent` on each read is what actually keeps file I/O off the main actor. Because
/// `SWIFT_APPROACHABLE_CONCURRENCY = YES` enables nonisolated-nonsending by default, a
/// merely `nonisolated async` method runs on *the caller's* executor — so a `@MainActor`
/// caller would drag every read onto the main actor while the type still looked correctly
/// annotated. `@concurrent` forces the hop onto the global executor instead.
///
/// `FileSystemSSHDirectoryReaderTests.readCompletesWhileTheMainActorIsBlocked` guards this:
/// it fails if `@concurrent` is removed.
nonisolated struct FileSystemSSHDirectoryReader: SSHDirectoryReading {
    /// `FileManager` is not `Sendable`, yet the port requires conformers to be — without
    /// this the warning becomes an error under the Swift 6 language mode. The exception is
    /// sound for the way it is used here: the adapter only ever reads through it, sets no
    /// delegate, and never mutates it, and the querying methods used below are documented as
    /// safe to call concurrently.
    nonisolated(unsafe) private let fileManager: FileManager

    /// - Parameter fileManager: injected so tests can exercise the adapter against a
    ///   scratch directory rather than the developer's own files.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @concurrent
    func directoryExists(at url: URL) async -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    @concurrent
    func fileExists(at url: URL) async -> Bool {
        fileManager.fileExists(atPath: url.path(percentEncoded: false))
    }

    @concurrent
    func entries(in url: URL) async throws(FileAccessError) -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw Self.accessError(for: url, from: error)
        }
    }

    @concurrent
    func contents(of url: URL) async throws(FileAccessError) -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw Self.accessError(for: url, from: error)
        }
    }

    /// Translates a Foundation failure into the port's vocabulary, so no `NSError` escapes
    /// the adapter and the caller can still tell absence from denial.
    ///
    /// `FileManager` reports these conditions through overlapping error domains, so both
    /// the Cocoa code and the underlying POSIX error are consulted.
    private static func accessError(for url: URL, from error: Error) -> FileAccessError {
        let error = error as NSError

        if let posix = posixCode(in: error) {
            switch posix {
            case ENOENT: return .directoryNotFound(url)
            case EACCES, EPERM: return .accessDenied(url)
            case ENOTDIR: return .unreadable(url)
            default: break
            }
        }

        switch error.code {
        case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
            return .directoryNotFound(url)
        case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
            return .accessDenied(url)
        default:
            return .unreadable(url)
        }
    }

    /// The POSIX code behind a Cocoa error, whether it is the error itself or the
    /// underlying error Foundation attached to it.
    private static func posixCode(in error: NSError) -> Int32? {
        let candidates = [error, error.userInfo[NSUnderlyingErrorKey] as? NSError].compactMap(\.self)
        return candidates
            .first { $0.domain == NSPOSIXErrorDomain }
            .map { Int32($0.code) }
    }
}
