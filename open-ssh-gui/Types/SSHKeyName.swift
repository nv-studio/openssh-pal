import Foundation

/// The base name a key pair's files share, validated.
///
/// The initializer is private to this file, so there is no construction path that skips the
/// rules: a name is obtained from `validated(_:)` — which applies the rules the user's input
/// must satisfy — or from `discovered(_:)`, which accepts a name that already came off a
/// directory listing. A caller holding one of these never has to wonder whether it was
/// checked.
///
/// The name is the *private* key's file name. The public key's name is derived by appending
/// the extension and the certificate's by appending its suffix, which is how every OpenSSH
/// tool derives them; `.pub` is therefore never supplied by a caller.
nonisolated struct SSHKeyName: Equatable, Hashable, Sendable, Comparable {

    /// The names OpenSSH owns inside the SSH directory.
    ///
    /// Held here, on the value type, rather than on a rule type, so that the validator and
    /// key discovery consult one list and cannot disagree about what is not a key.
    static let reservedNames: Set<String> = ["config", "known_hosts", "authorized_keys"]

    /// The extension OpenSSH appends to a private key's name to get its public key's name.
    static let publicKeyExtension = "pub"

    /// What `ssh(1)` appends to an identity path to find its certificate, per `ssh_config(5)`.
    static let certificateSuffix = "-cert.pub"

    let rawValue: String

    private init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }

    /// Applies the rules a user-supplied name must satisfy.
    ///
    /// Surrounding whitespace is trimmed rather than rejected: a trailing space is a typo
    /// with an obvious intent, and accepting it verbatim would produce a file name the user
    /// cannot see the end of.
    ///
    /// The collision rule is deliberately absent. It needs a directory listing, so it lives
    /// in `SSHKeyNameValidator` — which is the entry point both rename and creation use.
    static func validated(_ proposed: String) -> Result<SSHKeyName, SSHKeyNameError> {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard isPlainFileName(trimmed) else { return .failure(.notAPlainFileName(proposed)) }
        guard !hasPublicKeyExtension(trimmed) else {
            return .failure(.endsInPublicKeyExtension(proposed))
        }
        guard !reservedNames.contains(trimmed) else {
            return .failure(.reservedByOpenSSH(trimmed))
        }

        return .success(SSHKeyName(unchecked: trimmed))
    }

    /// Accepts a name that came from a directory listing rather than from the user.
    ///
    /// The reserved-name and `.pub` rules are not applied: those say what the user may
    /// *type*, not what the directory may contain. A file genuinely named `config.pub`
    /// still describes a pair, and refusing to represent it would drop it from the list
    /// instead of showing it.
    ///
    /// Returns `nil` for anything that could not name a single file. A directory listing
    /// cannot produce such an entry, so this is a total function rather than a trap.
    static func discovered(_ fileName: String) -> SSHKeyName? {
        guard !fileName.isEmpty, isPlainFileName(fileName) else { return nil }
        return SSHKeyName(unchecked: fileName)
    }

    /// Whether the name identifies one file inside a directory, rather than reaching out of
    /// it. `.` and `..` are rejected outright; everything else need only be separator-free.
    private static func isPlainFileName(_ candidate: String) -> Bool {
        candidate != "." && candidate != ".." && !candidate.contains("/")
    }

    private static func hasPublicKeyExtension(_ candidate: String) -> Bool {
        candidate.lowercased().hasSuffix("." + publicKeyExtension)
    }

    // MARK: - Derived locations

    /// Where the private key lives inside `directory`.
    func privateKeyURL(in directory: URL) -> URL {
        directory.appending(path: rawValue)
    }

    /// Where the public key lives — the private key's name plus the extension, which is how
    /// `ssh-keygen`, `ssh-add` and `IdentityFile` all derive it.
    func publicKeyURL(in directory: URL) -> URL {
        directory.appending(path: rawValue + "." + Self.publicKeyExtension)
    }

    /// Where a certificate for this pair would live, whether or not one exists.
    func certificateURL(in directory: URL) -> URL {
        directory.appending(path: rawValue + Self.certificateSuffix)
    }

    /// Every file an operation on this name could write, which is what a collision is
    /// computed against.
    func derivedURLs(in directory: URL) -> [URL] {
        [privateKeyURL(in: directory), publicKeyURL(in: directory), certificateURL(in: directory)]
    }

    static func < (lhs: SSHKeyName, rhs: SSHKeyName) -> Bool {
        lhs.rawValue.localizedStandardCompare(rhs.rawValue) == .orderedAscending
    }
}
