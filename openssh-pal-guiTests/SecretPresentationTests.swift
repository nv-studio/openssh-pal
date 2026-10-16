import Testing

/// The security claim of `SecretField` rests entirely on this type: a redacted presentation does
/// not carry the value, so there is nothing for a view, an accessibility label or a future
/// "simplification" to leak.
@Suite("Secret presentation state")
struct SecretPresentationTests {

    @Test("A redacted secret yields no value, which is what makes redaction structural")
    func redactedYieldsNoValue() {
        let presentation = SecretPresentation.redacted(placeholderLength: 32)

        #expect(presentation.value == nil)
        #expect(presentation.isRevealed == false)
    }

    @Test("A redacted secret still reports how long a placeholder to draw")
    func redactedReportsItsPlaceholderLength() {
        #expect(SecretPresentation.redacted(placeholderLength: 32).placeholderLength == 32)
    }

    @Test("A revealed secret yields the value the caller granted")
    func revealedYieldsTheValue() {
        let presentation = SecretPresentation.revealed("ssh-ed25519 AAAA")

        #expect(presentation.value == "ssh-ed25519 AAAA")
        #expect(presentation.isRevealed)
    }

    @Test("A revealed secret reports a placeholder length matching the value it holds")
    func revealedPlaceholderMatchesItsValue() {
        #expect(SecretPresentation.revealed("abcd").placeholderLength == 4)
    }
}
