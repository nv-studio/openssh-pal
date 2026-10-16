import Foundation

/// A draft every rule has accepted, in the form the editor writes.
///
/// Only `HostDraftValidator` produces one, so a value that reaches the editor has always been
/// checked. An absent optional means "not declared": the editor removes the directive.
nonisolated struct ValidatedHostDraft: Sendable, Equatable {
    /// Each pattern as one unescaped `Host` argument, negation included.
    let patterns: [String]
    let hostName: String?
    let user: String?
    let port: String?
    let keyChoice: HostKeyChoice

    /// The alias a created block is written with.
    var alias: String { patterns.first ?? "" }

    /// The same draft with a different key choice — for an edit whose key the user left as it
    /// was, which must not rewrite an `IdentityFile` that already names that key.
    func with(keyChoice: HostKeyChoice) -> ValidatedHostDraft {
        ValidatedHostDraft(patterns: patterns, hostName: hostName, user: user, port: port, keyChoice: keyChoice)
    }
}
