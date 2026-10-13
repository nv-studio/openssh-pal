import SwiftUI

/// Renders text the user may want to read character by character — a path, a fingerprint, a
/// fragment of configuration.
///
/// Truncates in the **middle** rather than the end, because the informative parts of a path are
/// at both ends and an elided tail hides the filename.
struct CodeText: View {

    let text: String
    var lineLimit: Int = 2

    var body: some View {
        Text(text)
            .font(Typography.code)
            .textSelection(.enabled)
            // Reserves the full line count whether or not the text fills it. The panel sizes
            // itself to its content, so a row that grew from one line to two while AppKit was
            // laying the panel out would make it re-enter layout. Owning the reservation here
            // means no surface has to reserve it on this component's behalf.
            .lineLimit(lineLimit, reservesSpace: true)
            .truncationMode(.middle)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Code text, including a path long enough to truncate") {
    VStack(alignment: .leading, spacing: Spacing.snug) {
        CodeText(text: "~/.ssh/config")
        CodeText(text: "SHA256:3Xq2wPl9kFzN0aBcDeFgHiJkLmNoPqRsTuVwXyZ01234")
        CodeText(text: "/Users/someone/Library/Containers/an/extremely/long/path/that/cannot/fit/id_ed25519.pub")
    }
    .padding(Spacing.loose)
    .frame(width: 320)
}
