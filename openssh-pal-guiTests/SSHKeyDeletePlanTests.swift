import Foundation
import Testing

@Suite("Delete plans")
nonisolated struct SSHKeyDeletePlanTests {

    private static let directory = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)

    private static func name(_ raw: String) throws -> SSHKeyName {
        try SSHKeyName.validated(raw).get()
    }

    private static func location(
        _ raw: String,
        privateKey: Bool = true,
        certificate: Bool = false
    ) throws -> SSHKeyPairLocation {
        let name = try name(raw)
        return SSHKeyPairLocation(
            name: name,
            publicKeyURL: name.publicKeyURL(in: directory),
            privateKeyURL: privateKey ? name.privateKeyURL(in: directory) : nil,
            certificateURL: certificate ? name.certificateURL(in: directory) : nil
        )
    }

    private static func file(_ name: String) -> URL {
        directory.appending(path: name)
    }

    // MARK: - 7.3 every file in the pair

    @Test("A pair with a certificate yields three removals")
    func pairWithCertificateYieldsThreeRemovals() throws {
        let plan = SSHKeyDeletePlan(location: try Self.location("work", certificate: true))

        #expect(plan.removals == [
            Self.file("work"),
            Self.file("work.pub"),
            Self.file("work-cert.pub"),
        ])
    }

    @Test("A pair without a certificate yields two removals")
    func pairWithoutCertificateYieldsTwoRemovals() throws {
        let plan = SSHKeyDeletePlan(location: try Self.location("work"))

        #expect(plan.removals == [Self.file("work"), Self.file("work.pub")])
    }

    @Test("A pair whose private key is absent removes only what it has")
    func absentPrivateKeyIsNotRemoved() throws {
        let plan = SSHKeyDeletePlan(location: try Self.location("orphan", privateKey: false))

        #expect(plan.removals == [Self.file("orphan.pub")])
    }

    // MARK: - ordering

    @Test("The private key is removed first, so a half-finished deletion leaves the public half")
    func privateKeyIsRemovedFirst() throws {
        let plan = SSHKeyDeletePlan(location: try Self.location("work", certificate: true))

        #expect(plan.removals.first == Self.file("work"))
    }

    // MARK: - 7.7 / 11.2 no bystander can appear

    @Test("A plan names only the identified pair's own files, whatever else the directory holds")
    func planCannotNameABystander() throws {
        let location = try Self.location("work", certificate: true)
        let plan = SSHKeyDeletePlan(location: location)

        // The plan is derived from the location alone. There is no listing, no pattern and
        // no directory scan it could widen through, so a file the user did not identify has
        // no path into it.
        #expect(Set(plan.removals) == Set(location.files))

        for removal in plan.removals {
            #expect(removal.lastPathComponent.hasPrefix("work"))
            #expect(removal.deletingLastPathComponent().standardizedFileURL
                == Self.directory.standardizedFileURL)
        }
    }

    @Test("Two pairs sharing a name prefix do not bleed into one another's plans")
    func aPrefixIsNotAMatch() throws {
        let plan = SSHKeyDeletePlan(location: try Self.location("work", certificate: true))

        #expect(!plan.removals.contains(Self.file("work2")))
        #expect(!plan.removals.contains(Self.file("work2.pub")))
    }

    // MARK: - the convenience over a presented pair

    @Test("A plan can be built from a presented pair, which is what the model holds")
    func planFromAPresentedPair() throws {
        let pair = SSHKeyPair(
            location: try Self.location("work", certificate: true),
            publicKey: .failure(.empty)
        )

        #expect(SSHKeyDeletePlan(pair: pair).removals == pair.location.files)
    }
}
