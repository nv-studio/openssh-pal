import Foundation

/// A `Host` or `Match` header and the lines it governs.
///
/// A block runs from its header to the line before the next header or to the end of the file.
/// It never spans files: OpenSSH saves and restores the active state around every included
/// file, which is what confines every edit to one file.
nonisolated struct ConfigBlock: Sendable, Equatable {

    nonisolated enum Kind: Sendable, Equatable {
        case host
        case match
    }

    let kind: Kind
    let lineRange: Range<Int>

    var headerLine: Int { lineRange.lowerBound }
}
