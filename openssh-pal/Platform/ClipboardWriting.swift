import Foundation

/// Placing text on the system clipboard.
///
/// The port takes **already-read text**, not a path. That is the whole of its security
/// design: it has no way to reach a file, so there is no code path by which a private key's
/// contents could reach the clipboard.
///
/// It also keeps AppKit out of every view, which is what lets the copy behaviour be asserted
/// without touching the real pasteboard.
protocol ClipboardWriting: Sendable {

    /// Replaces the clipboard's contents with `text`.
    ///
    /// Non-throwing: the pasteboard either takes the string or the app has nothing useful to
    /// say about it, and a public key is not worth an error path of its own.
    func write(_ text: String) async
}
