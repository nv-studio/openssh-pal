import Foundation
import Testing

@Suite("What a generation request carries")
struct SSHKeyGenerationRequestTests {

    private static let directory = URL(filePath: "/fabricated/keys", directoryHint: .isDirectory)

    private static func request(
        _ raw: String = "work_key",
        type: SSHKeyType = .ed25519,
        comment: String = "user@host"
    ) throws -> SSHKeyGenerationRequest {
        SSHKeyGenerationRequest(name: try SSHKeyName.validated(raw).get(), type: type, comment: comment)
    }

    @Test("A request holds a name, a type and a comment, and nothing secret")
    func requestHoldsNoSecret() throws {
        let request = try Self.request()

        #expect(request.name.rawValue == "work_key")
        #expect(request.type == .ed25519)
        #expect(request.comment == "user@host")
        // There is no passphrase to find: the request type has no field that could hold one,
        // which is why the generator takes it as a separate argument.
        #expect(!(request is any Encodable))
    }

    @Test("The request owns the whole argument list, so no caller assembles flags")
    func requestOwnsTheArgumentList() throws {
        let arguments = try Self.request(type: .rsa(.bits4096)).keygenArguments(in: Self.directory)

        #expect(Array(arguments.prefix(4)) == ["-t", "rsa", "-b", "4096"])
        #expect(arguments.contains("-C"))
        #expect(arguments.contains("user@host"))
        #expect(arguments.contains("-f"))
    }

    @Test("The target file is the private key inside the directory it was given")
    func targetIsThePrivateKeyPath() throws {
        let request = try Self.request()
        let arguments = request.keygenArguments(in: Self.directory)

        let target = request.name.privateKeyURL(in: Self.directory).path(percentEncoded: false)

        #expect(arguments.contains(target))
    }

    @Test("A request never spells -N, the flag that would put a passphrase in a process listing")
    func requestNeverUsesTheNewPassphraseFlag() throws {
        for type in SSHKeyType.allCases {
            let arguments = try Self.request(type: type).keygenArguments(in: Self.directory)

            #expect(!arguments.contains("-N"))
            #expect(!arguments.contains("-P"))
        }
    }
}
