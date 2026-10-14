import Foundation

/// One pattern of a `Host` line.
nonisolated struct HostPattern: Hashable, Sendable {

    /// The pattern without its leading `!`.
    let text: String

    let isNegated: Bool

    init(text: String, isNegated: Bool) {
        self.text = text
        self.isNegated = isNegated
    }

    /// Reads one unescaped `Host` argument, where a leading `!` negates it.
    init(parsing token: String) {
        if token.hasPrefix("!") {
            self.init(text: String(token.dropFirst()), isNegated: true)
        } else {
            self.init(text: token, isNegated: false)
        }
    }

    /// Whether the pattern can match more than one name.
    var hasWildcard: Bool {
        text.contains("*") || text.contains("?")
    }

    /// The pattern as it is written on a `Host` line, negation included.
    var token: String {
        isNegated ? "!" + text : text
    }
}
