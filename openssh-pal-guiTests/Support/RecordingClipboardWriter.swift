import Foundation

/// A `ClipboardWriting` conformer that records what reached it instead of touching the real
/// pasteboard.
///
/// Keeps the copy assertions out of the developer's own clipboard, and makes "the clipboard
/// was left alone" an assertion about an empty recorder rather than about system state no
/// test can see.
nonisolated final class RecordingClipboardWriter: ClipboardWriting, @unchecked Sendable {

    private let lock = NSLock()
    private var written: [String] = []

    init() {}

    /// Everything written, in order.
    var writes: [String] { lock.withLock { written } }

    /// The most recent write, or `nil` where nothing was written.
    var lastWrite: String? { lock.withLock { written.last } }

    /// Whether anything reached the clipboard at all.
    var isEmpty: Bool { lock.withLock { written.isEmpty } }

    func write(_ text: String) async {
        lock.withLock { written.append(text) }
    }
}
