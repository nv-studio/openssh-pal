import Foundation

/// Everything the key list can be showing.
///
/// A closed set of cases rather than an array plus an optional error, because the
/// distinction between "no keys found" and "could not be read" is the one this type exists
/// to protect: an unreadable directory presented as an empty array would tell the user they
/// have no keys.
nonisolated enum SSHKeyListState: Sendable, Equatable {
    /// The first enumeration has not finished yet.
    case loading

    /// The directory was listed. An empty array is "no keys found".
    case loaded([SSHKeyPair])

    /// The directory resolved but could not be listed.
    case unreadable(FileAccessError)

    /// There is no directory at all, because an override was rejected.
    case noDirectory(SSHDirectoryResolutionError)

    /// The pairs to present, which is none unless the directory was listed.
    var pairs: [SSHKeyPair] {
        guard case .loaded(let pairs) = self else { return [] }
        return pairs
    }

    /// Whether this is the empty state — a directory that was read and holds no key pair.
    ///
    /// Deliberately false for every failure case: that is the whole point of the type.
    var isEmptyListing: Bool {
        self == .loaded([])
    }

    /// Why there is no list, or `nil` where there is one.
    var failureReason: String? {
        switch self {
        case .loading, .loaded:
            nil
        case .unreadable(let error):
            error.reason
        case .noDirectory(let error):
            error.reason
        }
    }
}
