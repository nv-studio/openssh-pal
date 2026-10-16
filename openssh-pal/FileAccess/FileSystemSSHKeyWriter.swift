import Foundation

/// The production `SSHKeyWriting` conformer, backed by `FileManager`.
///
/// Together with `FileSystemSSHDirectoryReader` these are the only two types in the app
/// permitted to touch the file system, and this is the only one that changes anything.
///
/// It has **no create method and no write method**, by the port's design. The only code path
/// that brings a file into existence is `ssh-keygen`.
///
/// Both isolation annotations are load-bearing, for the reasons `FileSystemSSHDirectoryReader`
/// sets out: `nonisolated` on the type undoes the project's default main-actor isolation, and
/// `@concurrent` on each method is what actually keeps the work off the main actor — a merely
/// `nonisolated async` method would run on the caller's executor and so drag every mutation
/// onto the main actor while still looking correctly annotated.
///
/// `FileSystemSSHKeyWriterTests.mutationCompletesWhileTheMainActorIsBlocked` guards this.
nonisolated struct FileSystemSSHKeyWriter: SSHKeyWriting {

    /// The same documented exception `FileSystemSSHDirectoryReader` takes: `FileManager` is
    /// not `Sendable` while the port requires its conformers to be. The exception is sound
    /// for this usage — the adapter sets no delegate, never mutates the manager, and calls
    /// only methods documented as safe to call concurrently.
    nonisolated(unsafe) private let fileManager: FileManager

    /// - Parameter fileManager: injected so tests exercise the adapter against a scratch
    ///   directory rather than the developer's own files.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Moves one file, preserving its permissions.
    ///
    /// There is deliberately **no existence check** on the destination. `moveItem` refuses to
    /// replace an existing file, and relying on that refusal rather than on a check beforehand
    /// removes the window between the two in which a file could appear — and means even a
    /// defective validator upstream cannot destroy a bystander file through this call.
    ///
    /// Permissions need no handling either: `moveItem` within a volume is a rename, so the
    /// mode bits travel with the inode.
    @concurrent
    func move(from source: URL, to destination: URL) async throws(SSHKeyWriteError) {
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            throw Self.writeError(moving: source, to: destination, from: error)
        }
    }

    @concurrent
    func remove(at url: URL) async throws(SSHKeyWriteError) {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw Self.writeError(for: url, from: error)
        }
    }

    /// Translates a failed move, attributing it to whichever of the two files it concerns.
    ///
    /// A refusal to replace is the destination's condition; everything else is the source's.
    /// Getting this the wrong way round would show the user the name of a file that was never
    /// at risk.
    private static func writeError(
        moving source: URL,
        to destination: URL,
        from error: Error
    ) -> SSHKeyWriteError {
        let error = error as NSError

        if isExistingDestination(error) {
            return .destinationExists(destination)
        }
        return writeError(for: source, from: error)
    }

    /// Translates a Foundation failure into the port's vocabulary, so no `NSError` escapes
    /// the adapter and the caller can still tell absence from denial.
    ///
    /// Follows `FileAccessError`'s precedent in consulting both the Cocoa code and the
    /// underlying POSIX error: `FileManager` reports these conditions through overlapping
    /// domains, and a single check would collapse two conditions the user needs separated.
    private static func writeError(for url: URL, from error: Error) -> SSHKeyWriteError {
        let error = error as NSError

        if isExistingDestination(error) {
            return .destinationExists(url)
        }

        if let posix = posixCode(in: error) {
            switch posix {
            case ENOENT: return .notFound(url)
            case EACCES, EPERM, EROFS: return .accessDenied(url)
            default: break
            }
        }

        switch error.code {
        case NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileWriteInvalidFileNameError:
            return .notFound(url)
        case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
            return .accessDenied(url)
        default:
            return .failed(url)
        }
    }

    private static func isExistingDestination(_ error: NSError) -> Bool {
        if error.code == NSFileWriteFileExistsError { return true }
        return posixCode(in: error) == EEXIST
    }

    /// The POSIX code behind a Cocoa error, whether it is the error itself or the underlying
    /// error Foundation attached to it.
    private static func posixCode(in error: NSError) -> Int32? {
        let candidates = [error, error.userInfo[NSUnderlyingErrorKey] as? NSError].compactMap(\.self)
        return candidates
            .first { $0.domain == NSPOSIXErrorDomain }
            .map { Int32($0.code) }
    }
}
