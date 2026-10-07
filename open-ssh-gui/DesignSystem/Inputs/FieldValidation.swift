/// Whether a field's current contents are acceptable, as judged by the caller.
///
/// The component that renders this never decides it. Modelled as a closed type rather than a
/// `Bool` plus an optional message, so "valid, but here is the error" cannot be constructed.
enum FieldValidation: Sendable, Hashable {

    case valid

    /// Unacceptable, carrying the reason to show the user.
    case invalid(String)

    /// The reason, when there is one.
    var message: String? {
        switch self {
        case .valid: nil
        case .invalid(let message): message
        }
    }

    var isValid: Bool {
        self == .valid
    }
}
