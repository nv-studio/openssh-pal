import Testing

/// Tests assert on colour *roles*, never on rendered colour values. The role is the decision;
/// the colour is the rendering, and SwiftUI gives no way to inspect it.
@Suite("Colour role vocabulary")
struct ColorRoleTests {

    @Test("The vocabulary repeats no role")
    func rolesAreDistinct() {
        let all = ColorRole.allCases

        #expect(Set(all).count == all.count)
    }

    @Test("The vocabulary covers text, state, prominence, field chrome and containers")
    func vocabularyIsComplete() {
        let all = Set(ColorRole.allCases)

        #expect(all.isSuperset(of: [.primaryText, .secondaryText]))
        #expect(all.isSuperset(of: [.success, .warning, .failure]))
        #expect(all.isSuperset(of: [.prominent, .destructive]))
        #expect(all.isSuperset(of: [.fieldBorder, .fieldBackground, .separator]))
        #expect(all.isSuperset(of: [.containerBackground, .rowHover, .selectedTab]))
    }

    @Test("Every role resolves to an appearance, which also proves the catalog is in this target")
    func everyRoleResolves() {
        for role in ColorRole.allCases {
            _ = ColorRoleAppearance.style(for: role)
        }
    }
}
