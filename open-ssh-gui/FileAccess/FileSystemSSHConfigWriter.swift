import Foundation

/// The production `SSHConfigWriting` conformer.
///
/// Every change is a complete copy written to a hidden temporary file in the target's own
/// directory, flushed, and then renamed over the target — so a crash mid-write can never leave
/// a truncated `config`. `Data.write(options: .atomic)` is not used because its new file gets
/// default permissions instead of the original's, and because renaming onto a symbolic link
/// replaces the link: a `config` managed by a dotfiles tool would silently stop being one.
/// Links are followed instead, and the *target* is replaced.
///
/// Every target is checked after links are followed, against the SSH directory with its own
/// links followed, so neither side's spelling — `/var` against `/private/var` — can make a
/// file outside look inside.
///
/// Both isolation annotations are load-bearing, for the reasons `FileSystemSSHDirectoryReader`
/// sets out. `FileSystemSSHConfigWriterTests.writeCompletesWhileTheMainActorIsBlocked` guards
/// `@concurrent`.
nonisolated struct FileSystemSSHConfigWriter: SSHConfigWriting {

    /// Part of every temporary file's name. A crash between writing one and renaming it leaves
    /// it behind; its leading dot keeps an `Include` glob from reading it, and it is not cleaned
    /// up automatically because deleting a file the app cannot prove it wrote is worse.
    static let temporaryMarker = ".open-ssh-gui-tmp-"

    /// Owner read and write, which OpenSSH requires of a configuration file it did not create.
    static let ownerOnly: mode_t = 0o600

    init() {}

    @concurrent
    func resolvedLocation(of url: URL) async -> URL {
        Self.canonical(url)
    }

    @concurrent
    func backUpIfAbsent(
        _ file: URL,
        to backup: URL,
        within directory: SSHDirectory
    ) async throws(SSHConfigWriteError) -> BackupOutcome {
        let source = try Self.confined(file, to: directory)
        let destination = try Self.confined(backup, to: directory)
        let contents = try Self.read(source, reportingAs: file)

        let temporary = try Self.writeTemporary(contents, beside: destination, mode: Self.ownerOnly, reportingAs: backup)

        // Exclusive, so an existing backup — the one from before the app first touched the
        // file — is never replaced, and two attempts cannot race into one.
        guard renamex_np(temporary.filePath, destination.filePath, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            unlink(temporary.filePath)
            if code == EEXIST { return .alreadyPresent }
            throw Self.error(for: code, url: backup)
        }
        return .created
    }

    @concurrent
    func replace(
        _ file: URL,
        expecting expected: Data,
        with contents: Data,
        within directory: SSHDirectory
    ) async throws(SSHConfigWriteError) {
        let target = try Self.confined(file, to: directory)

        // Compared as late as possible, right before the rename. The window that remains is
        // microseconds long and accepted; watching the file for events is out of scope.
        guard try Self.read(target, reportingAs: file) == expected else {
            throw .changedOnDisk(file)
        }

        var status = stat()
        guard stat(target.filePath, &status) == 0 else { throw Self.error(for: errno, url: file) }

        let temporary = try Self.writeTemporary(contents, beside: target, mode: status.st_mode & 0o7777, reportingAs: file)

        guard rename(temporary.filePath, target.filePath) == 0 else {
            let code = errno
            unlink(temporary.filePath)
            throw Self.error(for: code, url: file)
        }
    }

    @concurrent
    func create(_ file: URL, with contents: Data, within directory: SSHDirectory) async throws(SSHConfigWriteError) {
        let target = try Self.confined(file, to: directory)
        let temporary = try Self.writeTemporary(contents, beside: target, mode: Self.ownerOnly, reportingAs: file)

        // `RENAME_EXCL` is atomic *and* never replaces a file that appeared in the meantime,
        // which an existence check followed by a rename could not promise.
        guard renamex_np(temporary.filePath, target.filePath, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            unlink(temporary.filePath)
            throw code == EEXIST ? .alreadyExists(file) : Self.error(for: code, url: file)
        }
    }

    // MARK: - Locations

    /// Where `url` really is: every symbolic link followed. A path that does not exist yet is
    /// resolved through its nearest existing ancestor.
    private static func canonical(_ url: URL) -> URL {
        if let resolved = realpath(url.filePath, nil) {
            defer { free(resolved) }
            return URL(filePath: String(cString: resolved))
        }

        let parent = url.deletingLastPathComponent()
        guard parent.filePath != url.filePath, !url.lastPathComponent.isEmpty else { return url.standardizedFileURL }
        return canonical(parent).appending(path: url.lastPathComponent)
    }

    /// `url` resolved, or `outsideDirectory` when it resolves outside `directory`.
    private static func confined(_ url: URL, to directory: SSHDirectory) throws(SSHConfigWriteError) -> URL {
        let target = canonical(url)
        let root = canonical(directory.url).filePath
        guard target.filePath.hasPrefix(root.hasSuffix("/") ? root : root + "/") else {
            throw .outsideDirectory(url)
        }
        return target
    }

    // MARK: - File operations

    private static func read(_ url: URL, reportingAs reported: URL) throws(SSHConfigWriteError) -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw Self.error(for: posixCode(in: error as NSError) ?? EIO, url: reported)
        }
    }

    /// Writes `contents` to a new hidden file beside `target`, with `mode`, flushed to disk.
    ///
    /// Created with `O_EXCL`, so it can never be an existing file — including one an attacker
    /// placed under a predictable name. Removed on every failure path.
    private static func writeTemporary(
        _ contents: Data,
        beside target: URL,
        mode: mode_t,
        reportingAs reported: URL
    ) throws(SSHConfigWriteError) -> URL {
        let temporary = target.deletingLastPathComponent()
            .appending(path: "." + target.lastPathComponent + temporaryMarker + UUID().uuidString)

        let descriptor = open(temporary.filePath, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, ownerOnly)
        guard descriptor >= 0 else { throw error(for: errno, url: reported) }

        var failure: Int32?
        contents.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count, let base = buffer.baseAddress {
                let written = write(descriptor, base + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    failure = errno
                    return
                }
                offset += written
            }
        }
        // Applied explicitly rather than left to `open`, whose mode the umask can narrow.
        if failure == nil, fchmod(descriptor, mode) != 0 { failure = errno }
        if failure == nil, fsync(descriptor) != 0 { failure = errno }
        close(descriptor)

        if let failure {
            unlink(temporary.filePath)
            throw error(for: failure, url: reported)
        }
        return temporary
    }

    // MARK: - Errors

    private static func error(for code: Int32, url: URL) -> SSHConfigWriteError {
        switch code {
        case ENOENT, ENOTDIR: .notFound(url)
        case EACCES, EPERM, EROFS: .accessDenied(url)
        case EEXIST: .alreadyExists(url)
        default: .failed(url)
        }
    }

    /// The POSIX code behind a Cocoa error, whether it is the error itself or the underlying
    /// error Foundation attached to it.
    private static func posixCode(in error: NSError) -> Int32? {
        let candidates = [error, error.userInfo[NSUnderlyingErrorKey] as? NSError].compactMap(\.self)
        if let posix = candidates.first(where: { $0.domain == NSPOSIXErrorDomain }) {
            return Int32(posix.code)
        }
        switch error.code {
        case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return ENOENT
        case NSFileReadNoPermissionError: return EACCES
        default: return nil
        }
    }
}

nonisolated extension URL {
    /// The path as the C file APIs take it.
    fileprivate var filePath: String { path(percentEncoded: false) }
}
