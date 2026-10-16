import Foundation

/// The only port through which the app changes a configuration file.
///
/// A **separate** port, for the same reason `SSHKeyWriting` is separate from
/// `SSHDirectoryReading`: neither existing port is widened. A component holding only this port
/// cannot move or delete a key, and the key port still cannot bring a file into existence.
///
/// Every mutating method takes the resolved `SSHDirectory` and refuses a target whose
/// **resolved** location — symbolic links followed — lies outside it. That is a backstop beneath
/// the model's own writability checks, not a substitute for them.
///
/// After any thrown error the target is byte-identical to what it was before the call.
///
/// `Sendable` so a `nonisolated` conformer can be stored by a `@MainActor` consumer.
protocol SSHConfigWriting: Sendable {

    /// Where `url` really is, symbolic links followed. A file that does not exist resolves
    /// through its parent directory.
    func resolvedLocation(of url: URL) async -> URL

    /// Copies `file` to `backup` unless something is already there, with owner-only
    /// permissions. An existing backup is left untouched: the first is the one worth keeping.
    func backUpIfAbsent(
        _ file: URL,
        to backup: URL,
        within directory: SSHDirectory
    ) async throws(SSHConfigWriteError) -> BackupOutcome

    /// Replaces `file`'s contents, but only if its current bytes still equal `expected` —
    /// which is how an edit made in a text editor since the form opened is never overwritten.
    ///
    /// Atomic and permission-preserving, and a symbolic link survives: its target is replaced.
    func replace(
        _ file: URL,
        expecting expected: Data,
        with contents: Data,
        within directory: SSHDirectory
    ) async throws(SSHConfigWriteError)

    /// Brings `file` into existence with owner-only permissions. Never replaces a file that
    /// appeared in the meantime.
    func create(_ file: URL, with contents: Data, within directory: SSHDirectory) async throws(SSHConfigWriteError)
}
