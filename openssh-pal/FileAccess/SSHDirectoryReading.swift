import Foundation

/// The single port through which the application reads the file system.
///
/// The protocol is deliberately read-only. Nothing here creates, modifies or deletes
/// anything, so a consumer that holds only this port cannot damage the user's SSH
/// directory — the guarantee is structural rather than conventional. A later feature that
/// needs to write declares a separate writing port; this one is never widened.
///
/// `Sendable` so that a `nonisolated` conformer can be stored by a `@MainActor` consumer.
protocol SSHDirectoryReading: Sendable {
    /// Whether a directory exists at `url`. `false` for a regular file.
    func directoryExists(at url: URL) async -> Bool

    /// Whether any file-system item exists at `url`.
    func fileExists(at url: URL) async -> Bool

    /// The immediate children of `url`, non-recursive, including dotfiles.
    func entries(in url: URL) async throws(FileAccessError) -> [URL]

    /// The full contents of the regular file at `url`.
    func contents(of url: URL) async throws(FileAccessError) -> Data
}
