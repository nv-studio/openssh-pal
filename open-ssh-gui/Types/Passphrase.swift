import Foundation

/// An entered passphrase, held so that it cannot be printed.
///
/// Both description conformances are load-bearing. Without them Swift's reflection renders a
/// struct's stored properties into any interpolated string, so a passphrase would reach a
/// log or an error message through code that never meant to read it. With them, the only way
/// to see the secret is to ask for it by name.
///
/// It is deliberately **not** `Codable`. There is nowhere this value should be written, so
/// the serialisation path does not exist rather than being avoided by convention.
///
/// **No claim is made about scrubbing memory.** The obligation this type can discharge is
/// retaining no reference: the form drops its passphrase on every exit path and the
/// generator's copy goes out of scope when generation returns. Nothing zeroes the bytes,
/// because nothing can — the text system held the passphrase before this type existed and
/// `String`'s copy-on-write buffers may hold copies beyond the app's reach. The protections
/// that *are* enforceable are structural and live elsewhere: never written to a file, never
/// in an argument list or an environment, never in an error reason.
nonisolated struct Passphrase: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {

    /// What a passphrase renders as wherever it is described.
    static let redactedMarker = "<redacted>"

    /// No passphrase, as a value. An unencrypted private key is a choice the user may make
    /// (8.8), so it is data rather than a missing value.
    static let none = Passphrase("")

    private let storage: String

    init(_ secret: String) {
        storage = secret
    }

    /// Whether the user left the passphrase blank, which leaves the private key unencrypted.
    var isEmpty: Bool {
        storage.isEmpty
    }

    /// The only accessor that yields the secret back.
    ///
    /// Named plainly so that every call site reading key material is findable in one search,
    /// rather than hidden behind a description or a `rawValue` that reads like any other
    /// wrapper.
    var secret: String {
        storage
    }

    /// Redacted — including its length, which is why the marker is a constant rather than a
    /// row of dots sized to the value.
    var description: String { Self.redactedMarker }

    var debugDescription: String { Self.redactedMarker }
}
