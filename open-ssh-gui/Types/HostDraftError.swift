import Foundation

/// Why one value of a host form was rejected.
nonisolated enum HostDraftError: Error, Sendable, Equatable {

    /// A character that cannot appear in a configuration value.
    nonisolated enum ForbiddenCharacter: Sendable, Equatable {
        case lineBreak
        case hash
        case doubleQuote

        var name: String {
            switch self {
            case .lineBreak: "a line break"
            case .hash: "#"
            case .doubleQuote: "a double quote (\")"
            }
        }
    }

    case empty
    case notASingleConcreteHost
    case duplicatesHost(String)
    case portOutOfRange
    case forbiddenCharacter(ForbiddenCharacter)
    case containsWhitespace

    var reason: String {
        switch self {
        case .empty:
            "A host alias is required."
        case .notASingleConcreteHost:
            "Enter one alias without spaces, *, ? or !: this form adds a single concrete host."
        case .duplicatesHost(let host):
            "Already configured as Host \(host)."
        case .portOutOfRange:
            "A port is a whole number from 1 to 65535."
        case .forbiddenCharacter(let character):
            "Cannot contain \(character.name)."
        case .containsWhitespace:
            "Cannot contain spaces."
        }
    }
}
