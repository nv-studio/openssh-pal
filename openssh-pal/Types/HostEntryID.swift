import Foundation

/// Which `Host` block an entry is, within one load.
///
/// Stable only for the load that produced it: an external edit can insert a block and shift
/// every ordinal after it. That is why a form carries an entry *and* the bytes it was read
/// from, never an identifier alone.
nonisolated struct HostEntryID: Hashable, Sendable {
    let file: URL

    /// The block's position among the `Host` blocks of its file, from zero.
    let ordinal: Int
}
