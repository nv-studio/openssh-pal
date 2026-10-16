import Foundation

/// Where a configuration file's one-time backup goes.
///
/// A hidden file beside the resolved file: glob(3) never matches a leading dot with a wildcard,
/// so `Include config.d/*` does not read it. An `Include` that matches dotfiles would, and then
/// the backup would load as a second copy of every host in it — so that location is refused,
/// naming the pattern, rather than used.
///
/// Pure.
nonisolated struct ConfigBackupLocation {

    static let suffix = ".openssh-pal-backup"

    init() {}

    func backupURL(for file: URL, avoiding includes: [GlobPath]) -> Result<URL, BackupLocationError> {
        let backup = file.deletingLastPathComponent().appending(path: "." + file.lastPathComponent + Self.suffix)
        let segments = GlobPath(path: backup.path(percentEncoded: false)).segments

        for include in includes where include.segments.count == segments.count {
            let matches = zip(include.segments, segments).allSatisfy { GlobPattern($0).matches($1) }
            if matches { return .failure(.matchedByInclude(include.path)) }
        }
        return .success(backup)
    }
}
