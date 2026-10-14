import Foundation

/// An absolute path that may contain glob(3) wildcards, split into its segments.
///
/// Held as segments because glob matches one directory level at a time: a `*` never crosses
/// a `/`.
nonisolated struct GlobPath: Sendable, Equatable {
    /// The path's components after the root, in order.
    let segments: [String]

    init(segments: [String]) {
        self.segments = segments
    }

    /// Splits an absolute path, dropping empty components so `//` and a trailing `/` do not
    /// produce segments that match nothing.
    init(path: String) {
        segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    var path: String {
        "/" + segments.joined(separator: "/")
    }
}
