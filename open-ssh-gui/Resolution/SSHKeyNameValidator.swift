import Foundation

/// The one entry point through which a key name is validated.
///
/// Rename and creation both come here, which is what keeps them applying the same rules
/// without either duplicating them. The rules a name can be judged by on its own belong to
/// `SSHKeyName`; this type adds the one rule that needs to know what the directory already
/// holds.
///
/// Pure: it is handed the listing and never reads a directory itself, so every rule below is
/// exercisable from fabricated values.
nonisolated struct SSHKeyNameValidator {

    init() {}

    /// Validates `proposed` for an operation that would write into `directory`.
    ///
    /// - Parameters:
    ///   - proposed: the name as the user typed it.
    ///   - directory: the directory the derived files would be written into.
    ///   - entries: that directory's current contents, as the reader listed them.
    ///   - current: the name being replaced, for a rename. Its own files are excluded from
    ///     the collision check, so renaming a pair to the name it already has is not
    ///     reported as colliding with itself.
    func validate(
        _ proposed: String,
        in directory: URL,
        against entries: [URL],
        replacing current: SSHKeyName?
    ) -> Result<SSHKeyName, SSHKeyNameError> {
        SSHKeyName.validated(proposed).flatMap { name in
            if let collision = collision(for: name, in: directory, against: entries, replacing: current) {
                return .failure(.wouldReplace(collision))
            }
            return .success(name)
        }
    }

    /// The first existing file the operation would replace, if any.
    ///
    /// Every file the operation could write is checked — private key, public key *and*
    /// certificate — not only the private key. Checking one of the three would let a rename
    /// quietly overwrite a public key or adopt an unrelated certificate.
    private func collision(
        for name: SSHKeyName,
        in directory: URL,
        against entries: [URL],
        replacing current: SSHKeyName?
    ) -> URL? {
        let existing = Set(entries.map(Self.key))
        let exempt = Set((current?.derivedURLs(in: directory) ?? []).map(Self.key))

        return name.derivedURLs(in: directory).first { candidate in
            let key = Self.key(candidate)
            return existing.contains(key) && !exempt.contains(key)
        }
    }

    /// One spelling per location, so a fixture written with a trailing slash or a `.` segment
    /// still matches the derived path it names.
    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }
}
