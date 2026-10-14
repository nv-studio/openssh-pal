import Foundation

/// What the user has typed into a host form, before any of it is judged.
nonisolated struct HostDraft: Sendable, Equatable {
    /// Create: one alias. Edit: the block's patterns, separated by whitespace.
    var patterns: String
    var hostName: String
    var user: String
    var port: String
    var keyChoice: HostKeyChoice

    static let empty = HostDraft(patterns: "", hostName: "", user: "", port: "", keyChoice: .none)
}
