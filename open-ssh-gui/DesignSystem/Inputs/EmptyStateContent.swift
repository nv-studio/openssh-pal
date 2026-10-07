/// What to show in place of a collection that has no items.
///
/// An empty list is not an error, so this is ordinary content rather than a failure state. The
/// optional symbol and action are modelled as optionals rather than signalled by empty strings,
/// so "no action" and "an action with no title" stay different things.
struct EmptyStateContent {

    /// Why the collection is empty, in the user's terms.
    let message: String

    /// An SF Symbol drawn above the message.
    let symbolName: String?

    /// Something the user can do about it.
    let action: Action?

    init(message: String, symbolName: String? = nil, action: Action? = nil) {
        self.message = message
        self.symbolName = symbolName
        self.action = action
    }

    /// The affordance offered alongside an empty state.
    struct Action {
        let title: String
        let perform: () -> Void

        init(title: String, perform: @escaping () -> Void) {
            self.title = title
            self.perform = perform
        }
    }
}
