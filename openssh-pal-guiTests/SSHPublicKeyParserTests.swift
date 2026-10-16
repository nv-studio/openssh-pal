import Foundation
import Testing

/// Every fixture below is a key `ssh-keygen` actually produced, paired with the fingerprint
/// and size `ssh-keygen -l` reported for it. The expectations were captured from OpenSSH's
/// own output once and embedded as constants, so the suite proves the parser agrees with
/// OpenSSH without launching it.
@Suite("Public key parsing")
nonisolated struct SSHPublicKeyParserTests {

    private static let parser = SSHPublicKeyParser()

    private static func parse(_ line: String) -> Result<SSHPublicKey, SSHPublicKeyError> {
        parser.parse(Data(line.utf8))
    }

    private static func parsed(_ line: String) throws -> SSHPublicKey {
        try parse(line).get()
    }

    // MARK: - Fixtures

    private enum Fixture {
        static let ed25519 = """
            ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHG/eTv0q9SPBgITfzHoiFX9BXBTCO4InzbH19BagKve user@host
            """
        static let ed25519Fingerprint = "SHA256:7LV+c2xGBpcU27QQPg0OOcVDg+MYEUTJUkuInY1Mii4"

        static let rsa2048 = """
            ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDDvUBbXr+OJ9RzFzhtchaD+NXVpwEvAZJAEhETFLSjR6qJB47DZC657lQz4P+ANA8uP2w7fHgAfm+eo/B5qWJxRb4oC37kteif7kIhshtgIrWmL9g3N21rL4v6U5irgLn/ZDBeMsqxgbpAv30MXXqB7STYPhNQsi8FRw+mHLyF/EBfe229dz3Ok3DNA+lXwvMZooxbNYV0PNYbpM+y2db4wBgOldZF7wnvyxGSWBMVRWTK4mxLrJw2YICBuDJzyOdAXuwuXGh2UxcWP7szMtwecIJZerHsKAMTKKdd6g9bXSGqA4HMCVcdRemU4K+GSDDPIlJWaBH6gDrIIDoa5bxP rsa comment with spaces
            """
        static let rsa2048Fingerprint = "SHA256:k6PaIlhfECZxxsWyq74N1iolU9WlTSovxs8nQK4dm1A"

        static let ecdsa256 = """
            ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBu9Yi54N/oBcNVCGkp8DiCiISoqK9ueDOOpJAN20YpdREhjuS0cFtYJIN65mK4jfVfwNvNZN/bpuHwb/Z81cEA= ecdsa@host
            """
        static let ecdsa256Fingerprint = "SHA256:eVwL+c0zVg3usZE9HeQDPGOpx60k3o35nhbV1joT9o4"

        /// Written by `ssh-keygen -C ""`, so the line ends in a separator with nothing after
        /// it. `ssh-keygen -l` reports "no comment" for this key.
        static let ecdsa521NoComment = "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBADXCoBf1dN9dJ1pH41zBn/3epzcQjRkjXv+qoXsjRIVCQi+kKAolisFNq17+IF6D6jTkeQQp7uaDyr7s/qdwQOOYgGPYaq5baqxaXItIsyLcyG/nj2QXlEsBZPaMLHxxd+5I3GbswCQKKy3yv0y1l4KjPbsGf/imBZBPeauqqMP08MW6w== "
        static let ecdsa521Fingerprint = "SHA256:sXrYOwejwKZle8Vz/mnx78bNrpw2dfQ+tKcwwTvjToI"
    }

    // MARK: - 2.3 the fingerprint OpenSSH itself reports

    @Test("An Ed25519 key's attributes match what ssh-keygen -l reports for it")
    func ed25519MatchesOpenSSH() throws {
        let key = try Self.parsed(Fixture.ed25519)

        #expect(key.algorithm == .ed25519)
        #expect(key.bitLength == 256)
        #expect(key.fingerprint.value == Fixture.ed25519Fingerprint)
        #expect(key.comment == "user@host")
    }

    @Test("An RSA key's attributes match what ssh-keygen -l reports, size derived from the modulus")
    func rsaMatchesOpenSSH() throws {
        let key = try Self.parsed(Fixture.rsa2048)

        #expect(key.algorithm == .rsa)
        #expect(key.bitLength == 2048)
        #expect(key.fingerprint.value == Fixture.rsa2048Fingerprint)
    }

    @Test("An ECDSA key's attributes match what ssh-keygen -l reports, size derived from the curve")
    func ecdsaMatchesOpenSSH() throws {
        let key = try Self.parsed(Fixture.ecdsa256)

        #expect(key.algorithm == .ecdsa(.nistp256))
        #expect(key.bitLength == 256)
        #expect(key.fingerprint.value == Fixture.ecdsa256Fingerprint)
        #expect(key.comment == "ecdsa@host")
    }

    @Test("A 521-bit ECDSA key is sized from its own curve, not from the first curve offered")
    func ecdsa521IsSizedFromItsCurve() throws {
        let key = try Self.parsed(Fixture.ecdsa521NoComment)

        #expect(key.algorithm == .ecdsa(.nistp521))
        #expect(key.bitLength == 521)
        #expect(key.fingerprint.value == Fixture.ecdsa521Fingerprint)
    }

    @Test("The fingerprint carries OpenSSH's prefix and no base64 padding")
    func fingerprintIsFormattedAsOpenSSHFormatsIt() throws {
        let key = try Self.parsed(Fixture.ed25519)

        #expect(key.fingerprint.value.hasPrefix("SHA256:"))
        #expect(!key.fingerprint.value.contains("="))
    }

    // MARK: - 2.4 comments

    @Test("A comment containing spaces survives intact, because the line splits into three fields")
    func commentWithSpacesSurvives() throws {
        let key = try Self.parsed(Fixture.rsa2048)

        #expect(key.comment == "rsa comment with spaces")
    }

    @Test("A key with no comment reports none rather than an empty string")
    func absentCommentIsNotAnEmptyString() throws {
        let key = try Self.parsed(Fixture.ecdsa521NoComment)

        #expect(key.comment == nil)
    }

    @Test("A key line carrying no third field at all reports no comment")
    func missingThirdFieldReportsNoComment() throws {
        let line = Fixture.ed25519.split(separator: " ").prefix(2).joined(separator: " ")

        #expect(try Self.parsed(line).comment == nil)
    }

    @Test("Extra separators between fields do not leak into the comment")
    func repeatedSeparatorsDoNotLeak() throws {
        let fields = Fixture.ed25519.split(separator: " ")
        let line = "\(fields[0])   \(fields[1])   \(fields[2])"

        #expect(try Self.parsed(line).comment == "user@host")
    }

    @Test("A trailing newline is not mistaken for part of the comment")
    func trailingNewlineIsIgnored() throws {
        #expect(try Self.parsed(Fixture.ed25519 + "\n").comment == "user@host")
        #expect(try Self.parsed(Fixture.ed25519 + "\r\n").comment == "user@host")
    }

    // MARK: - 2.2 the algorithm inside the blob is authoritative

    @Test("The algorithm comes from inside the blob, not from the line's first field")
    func inBlobAlgorithmWins() throws {
        let fields = Fixture.ed25519.split(separator: " ")
        let misdeclared = "ssh-rsa \(fields[1]) \(fields[2])"

        let key = try Self.parsed(misdeclared)

        // OpenSSH verifies against the name inside the blob, so that is what is presented.
        #expect(key.algorithm == .ed25519)
        #expect(key.bitLength == 256)
    }

    @Test("The fingerprint is computed over the blob alone, so the first field cannot change it")
    func fingerprintIgnoresTheDeclaredField() throws {
        let fields = Fixture.ed25519.split(separator: " ")
        let misdeclared = "nonsense \(fields[1])"

        #expect(try Self.parsed(misdeclared).fingerprint.value == Fixture.ed25519Fingerprint)
    }

    // MARK: - malformed input never traps

    @Test("Empty contents are reported as empty")
    func emptyContentsAreReported() {
        #expect(Self.parse("") == .failure(.empty))
        #expect(Self.parse("   \n\n") == .failure(.empty))
    }

    @Test("A single-field line is reported as malformed")
    func singleFieldIsMalformed() {
        #expect(Self.parse("ssh-ed25519") == .failure(.malformedLine))
    }

    @Test("A second field that is not base64 is reported as such")
    func nonBase64IsReported() {
        #expect(Self.parse("ssh-ed25519 !!!!not base64!!!!") == .failure(.notBase64))
    }

    @Test("A blob that ends inside a length-prefixed field is reported as truncated")
    func truncatedBlobIsReported() throws {
        let fields = Fixture.ed25519.split(separator: " ")
        let blob = try #require(Data(base64Encoded: String(fields[1])))

        // Keep the four length bytes and drop the name they promise.
        let truncated = blob.prefix(6).base64EncodedString()

        #expect(Self.parse("ssh-ed25519 \(truncated)") == .failure(.truncatedBlob))
    }

    @Test("A line with nothing after the algorithm is malformed rather than truncated")
    func lineWithNoBlobIsMalformed() {
        #expect(Self.parse("ssh-ed25519 ") == .failure(.malformedLine))
    }

    @Test("Arbitrary bytes do not trap, whatever they are")
    func arbitraryBytesDoNotTrap() {
        let inputs: [Data] = [
            Data([0x00, 0xFF, 0xFE, 0x01]),
            Data([0x00]),
            Data(repeating: 0x20, count: 64),
            Data("ssh-rsa AAAA".utf8),
            Data("\u{FFFD}\u{0000}".utf8),
        ]

        for input in inputs {
            // The assertion is that each returns rather than crashing; which failure it is
            // does not matter for an input that is not a key at all.
            _ = Self.parser.parse(input)
        }
    }

    // MARK: - an algorithm this app does not know

    @Test("An unknown algorithm is still fingerprinted, with its size marked unavailable")
    func unknownAlgorithmIsStillUseful() throws {
        // A blob whose first field names an algorithm this app has no sizing rule for.
        var blob = Data()
        let name = Data("sk-ssh-ed25519@openssh.com".utf8)
        blob.append(contentsOf: [0, 0, 0, UInt8(name.count)])
        blob.append(name)

        let key = try Self.parsed("sk-ssh-ed25519@openssh.com \(blob.base64EncodedString()) tok@host")

        #expect(key.algorithm == .other("sk-ssh-ed25519@openssh.com"))
        #expect(key.bitLength == nil)
        #expect(key.comment == "tok@host")
        #expect(key.fingerprint.value.hasPrefix("SHA256:"))
    }

    // MARK: - 2.2 nothing but the public key's bytes

    @Test("Parsing needs nothing but the bytes it was handed")
    func parsingNeedsOnlyTheBytes() throws {
        // No URL, no reader, no directory: the parser's whole input is `Data`, which is what
        // makes "never reads a private key" a property of its signature.
        let key = try Self.parsed(Fixture.ed25519)

        #expect(key.fingerprint.value == Fixture.ed25519Fingerprint)
    }
}
