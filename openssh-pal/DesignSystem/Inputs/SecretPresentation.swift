/// How much of a secret the caller has authorised showing.
///
/// The redacted case **does not carry the value**. That is the whole point of this type, and it
/// is not an optimisation to tidy away later: a `String` plus an `isRevealed: Bool` would put the
/// value in the view hierarchy while claiming it was hidden, where an accessibility label, a
/// debug description or a later logging statement could still reach it.
enum SecretPresentation: Sendable, Hashable {

    /// Hidden. Carries only how long a placeholder to draw.
    case redacted(placeholderLength: Int)

    /// Shown, because the caller said so.
    case revealed(String)

    /// The value, when the caller has granted it. `nil` is not a fallback here — it is the
    /// guarantee.
    var value: String? {
        switch self {
        case .redacted: nil
        case .revealed(let value): value
        }
    }

    /// How many placeholder characters to draw.
    var placeholderLength: Int {
        switch self {
        case .redacted(let length): length
        case .revealed(let value): value.count
        }
    }

    var isRevealed: Bool {
        value != nil
    }
}
