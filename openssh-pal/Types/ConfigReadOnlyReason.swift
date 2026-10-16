import Foundation

/// Why a configuration file cannot be written.
nonisolated enum ConfigReadOnlyReason: Sendable, Equatable {
    /// The file lies outside the resolved SSH directory, which every write is confined to.
    case outsideDirectory

    /// The file is not valid UTF-8, so it cannot be edited as text without changing bytes the
    /// user did not touch.
    case notUTF8

    /// The file is a symbolic link whose target lies outside the resolved SSH directory.
    case symbolicLinkOutsideDirectory

    var reason: String {
        switch self {
        case .outsideDirectory:
            "This file is outside the SSH directory, so the app does not change it."
        case .notUTF8:
            "This file is not UTF-8 text, so the app cannot edit it without risking its contents."
        case .symbolicLinkOutsideDirectory:
            "This file links to a location outside the SSH directory, so the app does not change it."
        }
    }
}
