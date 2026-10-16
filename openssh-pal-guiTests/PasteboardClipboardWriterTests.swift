import AppKit
import Foundation
import Testing

/// Driven against a uniquely named private pasteboard rather than the general one, so the
/// suite never touches the developer's own clipboard.
@Suite("Pasteboard clipboard writer")
struct PasteboardClipboardWriterTests {

    private static let publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHG/eTv0q9SPBgITfzHoiFX9BXBTCO4InzbH19BagKve user@host"

    /// A scratch pasteboard, released when the body returns.
    private static func withPasteboard<T>(
        perform body: (NSPasteboard) async throws -> T
    ) async throws -> T {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("openssh-pal-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        return try await body(pasteboard)
    }

    @Test("The supplied line reaches the clipboard exactly as it was handed over")
    func suppliedLineIsWrittenVerbatim() async throws {
        try await Self.withPasteboard { pasteboard in
            let writer: any ClipboardWriting = PasteboardClipboardWriter(pasteboard: pasteboard)

            await writer.write(Self.publicKey)

            #expect(pasteboard.string(forType: .string) == Self.publicKey)
        }
    }

    @Test("A trailing newline from the file does not reach the clipboard")
    func trailingNewlineIsDropped() async throws {
        try await Self.withPasteboard { pasteboard in
            let writer: any ClipboardWriting = PasteboardClipboardWriter(pasteboard: pasteboard)

            // A `.pub` file ends in a newline. Pasting that into a web form would submit a
            // line break along with the key, so the one place that touches the clipboard is
            // where it is removed.
            await writer.write(Self.publicKey + "\n")

            #expect(pasteboard.string(forType: .string) == Self.publicKey)
        }
    }

    @Test("A CRLF ending is dropped too")
    func crlfEndingIsDropped() async throws {
        try await Self.withPasteboard { pasteboard in
            let writer = PasteboardClipboardWriter(pasteboard: pasteboard)

            await writer.write(Self.publicKey + "\r\n")

            #expect(pasteboard.string(forType: .string) == Self.publicKey)
        }
    }

    @Test("Spaces inside the key line are preserved, including a comment with spaces")
    func internalSpacesSurvive() async throws {
        try await Self.withPasteboard { pasteboard in
            let line = "ssh-rsa AAAAB3Nz a comment with spaces"
            let writer = PasteboardClipboardWriter(pasteboard: pasteboard)

            await writer.write(line + "\n")

            #expect(pasteboard.string(forType: .string) == line)
        }
    }

    @Test("A second copy replaces the first rather than appending to it")
    func asecondCopyReplacesTheFirst() async throws {
        try await Self.withPasteboard { pasteboard in
            let writer = PasteboardClipboardWriter(pasteboard: pasteboard)

            await writer.write("first")
            await writer.write("second")

            #expect(pasteboard.string(forType: .string) == "second")
        }
    }

    @Test("The clipboard is left holding the key afterwards, since a public key is not a secret")
    func clipboardIsNotCleared() async throws {
        try await Self.withPasteboard { pasteboard in
            let writer = PasteboardClipboardWriter(pasteboard: pasteboard)

            await writer.write(Self.publicKey)

            // No expiry, no clearing: the user is expected to paste this somewhere, possibly
            // minutes later.
            #expect(pasteboard.string(forType: .string) == Self.publicKey)
            #expect(pasteboard.string(forType: .string) == Self.publicKey)
        }
    }
}
