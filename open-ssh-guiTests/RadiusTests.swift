import Foundation
import Testing

@Suite("Corner radius scale")
struct RadiusTests {

    @Test("The scale is readable without constructing a view")
    func readableWithoutAView() {
        #expect(Radius.control > 0)
    }

    @Test("A control is no more rounded than the panel containing it")
    func controlIsNotRounderThanThePanel() {
        #expect(Radius.control <= Radius.panel)
    }
}
