import Foundation
import Testing

@Suite("Passphrase redaction")
struct PassphraseTests {

    private static let secret = "correct horse battery staple"

    @Test("Interpolating a passphrase yields the marker, not the secret")
    func interpolationIsRedacted() {
        let passphrase = Passphrase(Self.secret)

        let message = "Generation failed with \(passphrase)"

        #expect(message.contains(Passphrase.redactedMarker))
        #expect(!message.contains(Self.secret))
    }

    @Test("A debug description is redacted too, so a breakpoint dump cannot leak it")
    func debugDescriptionIsRedacted() {
        let passphrase = Passphrase(Self.secret)

        #expect(String(reflecting: passphrase) == Passphrase.redactedMarker)
        #expect(passphrase.debugDescription == Passphrase.redactedMarker)
    }

    @Test("An empty passphrase is redacted as well, so its length is not observable")
    func emptyPassphraseIsAlsoRedacted() {
        #expect("\(Passphrase.none)" == Passphrase.redactedMarker)
    }

    @Test("A passphrase refuses serialisation, so it cannot be written anywhere")
    func passphraseIsNotSerialisable() {
        let passphrase = Passphrase(Self.secret)

        // Conformance is checked at run time because the absence of a conformance cannot be
        // asserted at compile time. If someone adds `Codable` to make a type store nicely,
        // this fails rather than the passphrase quietly reaching a file.
        #expect(!(passphrase is any Encodable))
        #expect(!(passphrase is any Decodable))
    }

    @Test("No passphrase is a value rather than a sentinel")
    func absenceIsAValue() {
        #expect(Passphrase.none.isEmpty)
        #expect(Passphrase("").isEmpty)
        #expect(Passphrase("") == Passphrase.none)
        #expect(!Passphrase(Self.secret).isEmpty)
    }

    @Test("The single accessor returns the entered bytes, which is how the generator gets them")
    func theAccessorReturnsTheSecret() {
        #expect(Passphrase(Self.secret).secret == Self.secret)
        #expect(Passphrase.none.secret.isEmpty)
    }

    @Test("Two passphrases compare, which is what lets a mismatch be caught before generation")
    func passphrasesCompare() {
        #expect(Passphrase("a") == Passphrase("a"))
        #expect(Passphrase("a") != Passphrase("b"))
    }
}
