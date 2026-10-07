/// What a status indicator can report.
///
/// A closed set, so "reachable and failing" is not expressible. Each case projects both an icon
/// and a colour role: relying on colour alone would make the states indistinguishable to a user
/// who cannot separate them, which is why the icons are asserted to be distinct too.
enum StatusRole: Sendable, Hashable, CaseIterable {

    /// The operation succeeded, or the resource is reachable.
    case success

    /// Worth the user's attention, but not a failure.
    case warning

    /// The operation failed, or the resource cannot be reached.
    case failure

    /// Not settled yet.
    case inProgress

    /// The SF Symbol drawn beside the message.
    var symbolName: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        case .inProgress: "ellipsis.circle"
        }
    }

    /// The colour the icon is tinted with.
    var colorRole: ColorRole {
        switch self {
        case .success: .success
        case .warning: .warning
        case .failure: .failure
        case .inProgress: .secondaryText
        }
    }
}
