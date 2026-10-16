/// Every colour this project uses, named by intent rather than by hue.
///
/// This is a pure value with no SwiftUI involvement, which is deliberate: it is the thing tests
/// assert on. The rendered colour is unobservable from a test, so the *decision* — which role a
/// state deserves — is what gets verified, and `ColorRoleAppearance` is the only place that turns
/// a role into something drawable.
nonisolated enum ColorRole: Sendable, Hashable, CaseIterable {

    /// Body text and a control's own label.
    case primaryText

    /// Supporting text, and a status that is still settling.
    case secondaryText

    /// An operation that succeeded, or a resource that is reachable.
    case success

    /// A condition the user should notice but that is not a failure.
    case warning

    /// An operation that failed, or a resource that cannot be reached.
    case failure

    /// An action that destroys something irreversibly.
    case destructive

    /// The one action a surface wants the user to take.
    case prominent

    /// The outline of an editable field.
    case fieldBorder

    /// The fill behind an editable field.
    case fieldBackground

    /// A hairline between groups.
    case separator
}
