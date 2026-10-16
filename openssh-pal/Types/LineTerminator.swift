import Foundation

/// How a configuration line ends.
///
/// Recorded per line, and once per file as the *dominant* terminator, because a line the app
/// adds has to end the way the user's own lines do: a CRLF file that gains one LF line is a
/// file a user can tell a GUI touched.
nonisolated enum LineTerminator: Sendable, Equatable {
    case lf
    case crlf

    /// The terminator's bytes, which is what a written line ends with.
    var bytes: [UInt8] {
        switch self {
        case .lf: [0x0A]
        case .crlf: [0x0D, 0x0A]
        }
    }
}
