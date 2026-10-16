import Foundation

/// What one `IdentityFile` value turned out to name.
nonisolated enum KeyAssociation: Sendable, Equatable {
    /// A key pair the Keys tab lists.
    case listed(SSHKeyName)

    /// A concrete path that is not a listed key pair. Shown as written.
    case unlisted(raw: String)

    /// A value the app will not resolve without a connection. Shown as written.
    case unresolved(raw: String, UnresolvableReason)

    /// `IdentityFile none`.
    case disabled
}
