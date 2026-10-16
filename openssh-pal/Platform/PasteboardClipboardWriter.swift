import AppKit
import Foundation

/// The production `ClipboardWriting` conformer, backed by `NSPasteboard`.
///
/// This is the only type in the app that imports AppKit for the pasteboard, which is what
/// keeps the framework out of every view and lets the copy behaviour be asserted without
/// touching the developer's own clipboard.
///
/// It takes text, never a path, so there is no code path by which it could read — let alone
/// copy — a private key.
///
/// Nothing clears or expires the clipboard afterwards. A public key is not a secret, and the
/// user is expected to paste it somewhere, possibly minutes later.
nonisolated struct PasteboardClipboardWriter: ClipboardWriting {

    /// `NSPasteboard` is not `Sendable` while the port requires its conformers to be. The
    /// exception is sound here: the adapter holds the pasteboard immutably and the two calls
    /// it makes are the pasteboard's own, documented, thread-safe entry points.
    nonisolated(unsafe) private let pasteboard: NSPasteboard

    /// - Parameter pasteboard: injected so tests drive a private pasteboard rather than the
    ///   general one.
    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Replaces the clipboard's contents with `text`, as one line.
    ///
    /// The trailing newline is removed because a `.pub` file carries one and pasting it into
    /// a web form would submit a line break along with the key. Nothing else about the text
    /// is touched — the spaces inside a comment, in particular, travel through unchanged.
    func write(_ text: String) async {
        pasteboard.clearContents()
        pasteboard.setString(Self.singleLine(text), forType: .string)
    }

    private static func singleLine(_ text: String) -> String {
        var line = Substring(text)
        while let last = line.last, last.isNewline {
            line = line.dropLast()
        }
        return String(line)
    }
}
