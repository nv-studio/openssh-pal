import SwiftUI
import Testing

@Suite("Typography tokens")
struct TypographyTests {

    @Test("Every token is distinct, so no two roles collapse into one appearance")
    func tokensAreDistinct() {
        let all = Typography.all

        #expect(Set(all).count == all.count)
    }

    @Test("The tokens are readable without constructing a view")
    func readableWithoutAView() {
        #expect(Typography.all.count >= 6)
    }
}
