import Foundation

/// The fields of a host form that can be rejected.
nonisolated enum HostDraftField: Hashable, Sendable, CaseIterable {
    case patterns
    case hostName
    case user
    case port

    /// The keyword the field writes, which is also how it is labelled.
    var title: String {
        switch self {
        case .patterns: "Host"
        case .hostName: "HostName"
        case .user: "User"
        case .port: "Port"
        }
    }
}
