import Testing

@Suite("Empty state content")
struct EmptyStateContentTests {

    @Test("An empty state can carry a message alone")
    func messageAlone() {
        let content = EmptyStateContent(message: "No hosts in this configuration")

        #expect(content.message == "No hosts in this configuration")
        #expect(content.symbolName == nil)
        #expect(content.action == nil)
    }

    @Test("An empty state can carry a symbol alongside its message")
    func messageWithSymbol() {
        let content = EmptyStateContent(message: "No keys", symbolName: "key")

        #expect(content.symbolName == "key")
        #expect(content.action == nil)
    }

    @Test("An empty state can offer an action, and invoking it runs the caller's closure")
    func messageWithAction() {
        var invoked = false
        let content = EmptyStateContent(
            message: "No hosts",
            action: EmptyStateContent.Action(title: "Add a host") { invoked = true }
        )

        content.action?.perform()

        #expect(invoked)
        #expect(content.action?.title == "Add a host")
    }
}
