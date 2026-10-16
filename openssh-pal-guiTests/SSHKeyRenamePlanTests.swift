import Foundation
import Testing

@Suite("Rename plans and their inverse")
nonisolated struct SSHKeyRenamePlanTests {

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

    private static func plan(
        _ raw: String = "old_key",
        to newRaw: String = "new_key",
        privateKey: Bool = true,
        certificate: Bool = false
    ) throws -> SSHKeyRenamePlan {
        SSHKeyRenamePlan(
            location: try location(raw, privateKey: privateKey, certificate: certificate),
            newName: try name(newRaw)
        )
    }

    private static func file(_ name: String) -> URL {
        directory.appending(path: name)
    }

    // MARK: - 4.2 every file in the pair moves

    @Test("A complete pair with a certificate moves all three of its files")
    func completePairMovesThreeFiles() throws {
        let plan = try Self.plan(certificate: true)

        #expect(plan.moves == [
            .init(from: Self.file("old_key"), to: Self.file("new_key")),
            .init(from: Self.file("old_key.pub"), to: Self.file("new_key.pub")),
            .init(from: Self.file("old_key-cert.pub"), to: Self.file("new_key-cert.pub")),
        ])
    }

    @Test("A pair with no certificate moves only the two files it has")
    func pairWithoutCertificateMovesTwoFiles() throws {
        #expect(try Self.plan().moves.count == 2)
    }

    @Test("A pair whose private key is absent moves only what exists")
    func absentPrivateKeyIsNotMoved() throws {
        let plan = try Self.plan(privateKey: false)

        #expect(plan.moves == [.init(from: Self.file("old_key.pub"), to: Self.file("new_key.pub"))])
    }

    // MARK: - ordering

    @Test("The private key moves first, so a half-finished rename leaves the identifying half")
    func privateKeyMovesFirst() throws {
        let plan = try Self.plan(certificate: true)

        #expect(plan.moves.first?.from == Self.file("old_key"))
        #expect(plan.moves.last?.from == Self.file("old_key-cert.pub"))
    }

    // MARK: - 4.3 the public key's destination is derived

    @Test("The public key's destination is the private key's destination plus the extension")
    func publicDestinationExtendsThePrivateOne() throws {
        let plan = try Self.plan()

        let privateDestination = try #require(plan.moves.first).to.path(percentEncoded: false)
        let publicDestination = try #require(plan.moves.last).to.path(percentEncoded: false)

        #expect(publicDestination == privateDestination + ".pub")
    }

    @Test("A pair whose public key moves alone still derives its destination the same way")
    func publicDestinationIsDerivedWithoutAPrivateKey() throws {
        let plan = try Self.plan(privateKey: false)

        #expect(try #require(plan.moves.first).to == Self.file("new_key.pub"))
    }

    // MARK: - 11.1 containment

    @Test("Every destination stays inside the pair's own directory")
    func destinationsStayInsideTheDirectory() throws {
        let plan = try Self.plan(certificate: true)

        for move in plan.moves {
            #expect(move.from.deletingLastPathComponent().standardizedFileURL
                == Self.directory.standardizedFileURL)
            #expect(move.to.deletingLastPathComponent().standardizedFileURL
                == Self.directory.standardizedFileURL)
        }
    }

    // MARK: - 4.6 the inverse of any prefix

    @Test("The inverse of every prefix length undoes exactly the steps that completed")
    func inverseOfEveryPrefixIsCorrect() throws {
        let plan = try Self.plan(certificate: true)

        for completed in 0...plan.moves.count {
            let inverse = plan.inverse(ofCompleted: completed)

            #expect(inverse.count == completed)

            // Undoing runs backwards, so the most recent move is the first to be reversed.
            let expected = plan.moves.prefix(completed).reversed().map {
                SSHKeyRenamePlan.Move(from: $0.to, to: $0.from)
            }
            #expect(inverse == expected)
        }
    }

    @Test("Nothing completed means nothing to undo")
    func inverseOfNothingIsEmpty() throws {
        #expect(try Self.plan(certificate: true).inverse(ofCompleted: 0).isEmpty)
    }

    @Test("A count beyond the plan's own length is clamped rather than trapping")
    func inverseIsClampedToThePlan() throws {
        let plan = try Self.plan(certificate: true)

        #expect(plan.inverse(ofCompleted: 99).count == plan.moves.count)
        #expect(plan.inverse(ofCompleted: -1).isEmpty)
    }

    @Test("Applying the inverse of the whole plan returns every file to where it started")
    func fullInverseRestoresEveryOriginalPath() throws {
        let plan = try Self.plan(certificate: true)

        let restored = Set(plan.inverse(ofCompleted: plan.moves.count).map(\.to))

        #expect(restored == Set(plan.moves.map(\.from)))
    }

    // MARK: - 4.4 contents are untouched

    @Test("A plan is nothing but moves, so no file's contents can be changed by executing one")
    func aPlanOnlyMoves() throws {
        let plan = try Self.plan(certificate: true)

        // A `Move` carries two locations and no payload: there is no field through which a
        // plan could express a change to a file's contents, including the comment inside a
        // public key.
        #expect(plan.moves.allSatisfy { $0.from != $0.to })
    }

    // MARK: - a rename to the same name

    @Test("A rename to the name the pair already has plans no move at all")
    func renameToTheSameNamePlansNothing() throws {
        let plan = try Self.plan("same", to: "same", certificate: true)

        #expect(plan.moves.isEmpty)
    }

    // MARK: - the convenience over a presented pair

    @Test("A plan can be built from a presented pair, which is what the model holds")
    func planFromAPresentedPair() throws {
        let pair = SSHKeyPair(location: try Self.location("old_key"), publicKey: .failure(.empty))

        let plan = SSHKeyRenamePlan(pair: pair, newName: try Self.name("new_key"))

        #expect(plan.moves == SSHKeyRenamePlan(location: pair.location, newName: try Self.name("new_key")).moves)
    }
}
