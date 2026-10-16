import Foundation

/// What the panel shows for one key pair.
///
/// An extension rather than a type of its own, because these are projections of a value and
/// belong beside it — the exception to the one-type-per-file rule is deliberate. They live in
/// `MenuBar/` rather than with `SSHKeyPair` in `Types/` because `StatusRole` belongs to the
/// Design System, and `Types/` is a dependency root that may not reach into it.
///
/// Following `SSHDirectoryStatus`: a view that had to work out what to show would be a view
/// that could not be reasoned about without reading it, and none of this would be testable
/// without rendering something.
extension SSHKeyPair {

    /// The attributes, in one line: what the key is, how big, who it belongs to.
    ///
    /// An absent comment contributes nothing rather than a placeholder, and a size that could
    /// not be derived says so instead of showing a guess.
    var attributeSummary: String {
        guard let key = parsedPublicKey else {
            return parseFailure?.reason(for: location.publicKeyURL.lastPathComponent) ?? ""
        }

        var parts = [key.algorithm.displayName]

        if let bitLength = key.bitLength {
            parts.append("\(bitLength) bits")
        } else {
            parts.append("size unavailable")
        }

        if let comment = key.comment, !comment.isEmpty {
            parts.append(comment)
        }

        if hasCertificate {
            parts.append("certificate")
        }

        return parts.joined(separator: " · ")
    }

    /// What the key is and how big, as one value: the two are read together and a key whose
    /// algorithm fixes its size — Ed25519 — would otherwise get a row saying nothing.
    var typeText: String {
        guard let key = parsedPublicKey else { return unavailableValue }

        guard let bitLength = key.bitLength else {
            return "\(key.algorithm.displayName), size unavailable"
        }
        return "\(key.algorithm.displayName), \(bitLength) bits"
    }

    /// The comment, or a dash where the key carries none.
    ///
    /// A dash rather than a substituted placeholder: "no comment" is a fact about the key, and
    /// inventing `user@host` for it would be a different key's comment.
    var commentText: String {
        guard let comment = parsedPublicKey?.comment, !comment.isEmpty else { return unavailableValue }
        return comment
    }

    /// What an attribute that could not be derived shows.
    private var unavailableValue: String { "—" }

    /// The fingerprint, or a dash where it could not be derived.
    var fingerprintText: String {
        parsedPublicKey?.fingerprint.value ?? unavailableValue
    }

    /// The state of this entry, in the design system's vocabulary.
    ///
    /// A public key that cannot be read or parsed is a failure for *this entry* and nothing
    /// more — the rest of the list is unaffected. A missing private key is a warning rather
    /// than a failure: the entry is real and usable for some purposes, it just cannot
    /// authenticate.
    var statusRole: StatusRole {
        if parseFailure != nil { return .failure }
        if isPrivateKeyMissing { return .warning }
        return .success
    }

    /// The words beside the entry's indicator. Never empty, so the row is never a bare glyph.
    var statusMessage: String {
        if let failure = parseFailure {
            return failure.reason(for: location.publicKeyURL.lastPathComponent)
        }
        if isPrivateKeyMissing {
            return "Private key is missing — only \(location.publicKeyURL.lastPathComponent) is here."
        }
        return "Complete key pair."
    }
}
