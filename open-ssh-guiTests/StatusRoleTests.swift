import Testing

@Suite("Status vocabulary")
struct StatusRoleTests {

    @Test("No two states share an icon, so the states are separable without colour")
    func iconsAreDistinct() {
        let symbols = StatusRole.allCases.map(\.symbolName)

        #expect(Set(symbols).count == symbols.count)
    }

    @Test("No two states share a colour role either")
    func colourRolesAreDistinct() {
        let roles = StatusRole.allCases.map(\.colorRole)

        #expect(Set(roles).count == roles.count)
    }

    @Test("The vocabulary covers success, warning, failure and work in progress")
    func vocabularyIsComplete() {
        #expect(Set(StatusRole.allCases) == [.success, .warning, .failure, .inProgress])
    }

    @Test("Every case projects a non-empty icon name")
    func everyCaseHasAnIcon() {
        for role in StatusRole.allCases {
            #expect(role.symbolName.isEmpty == false)
        }
    }
}
