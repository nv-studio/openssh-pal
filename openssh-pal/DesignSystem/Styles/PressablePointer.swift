import SwiftUI

extension View {

    /// Shows the pointing-hand cursor while the pointer is over something that responds to a
    /// click, so every pressable in the panel announces itself the same way.
    ///
    /// The one place the cursor is chosen: the button style, the tab bar, the list rows and the
    /// native controls all go through here rather than naming a pointer style themselves. A
    /// disabled control keeps the system cursor, since clicking it does nothing.
    func pressablePointer(isEnabled: Bool = true) -> some View {
        pointerStyle(isEnabled ? .link : nil)
    }
}
