import Foundation
import Testing

/// The spacing scale. Tokens are plain values, so they are assertable without a view — which is
/// the property that lets this layer be tested at all.
@Suite("Spacing scale")
struct SpacingTests {

    @Test("The scale is readable without constructing a view")
    func readableWithoutAView() {
        #expect(Spacing.regular > 0)
        #expect(Spacing.ascending.isEmpty == false)
    }

    @Test("The scale ascends and repeats no value, so a larger name always means more space")
    func scaleAscendsWithoutDuplicates() {
        let scale = Spacing.ascending

        #expect(scale == scale.sorted())
        #expect(Set(scale).count == scale.count)
    }
}
