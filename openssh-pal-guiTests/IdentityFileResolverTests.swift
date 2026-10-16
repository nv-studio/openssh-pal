import Foundation
import Testing

/// An `IdentityFile` value is resolved only as far as it can be without a connection. A value
/// that cannot is reported with the reason, never guessed at — a wrong guess would associate a
/// host with the wrong key.
@Suite("Identity file resolver")
nonisolated struct IdentityFileResolverTests {

    private static let home = URL(filePath: "/fabricated/home")

    private static let context = IdentityResolutionContext(
        homeDirectory: home,
        sshDirectory: SSHDirectory(url: URL(filePath: "/fabricated/keys")),
        userName: "alice",
        defaultDirectory: home.appending(path: SSHDirectoryResolver.directoryName)
    )

    private static func resolve(_ argument: String) -> IdentityReference.Resolution {
        let reference = IdentityFileResolver().resolve(argument, in: context)
        #expect(reference.raw == argument)
        return reference.resolution
    }

    @Test(
        "Tilde, %d, %u and %% resolve to a concrete path",
        arguments: [
            ("~/keys/id_work", "/fabricated/home/keys/id_work"),
            ("%d/keys/id_work", "/fabricated/home/keys/id_work"),
            ("/srv/%u/id", "/srv/alice/id"),
            ("/srv/100%%/id", "/srv/100%/id"),
            ("~/%u", "/fabricated/home/alice"),
            ("/fabricated/keys/./sub/../id", "/fabricated/keys/id"),
        ]
    )
    func resolvable(_ argument: String, _ path: String) {
        #expect(Self.resolve(argument) == .path(URL(filePath: path)))
    }

    @Test("The literal none disables identity files")
    func none() {
        #expect(Self.resolve("none") == .disabled)
    }

    @Test(
        "Anything that needs a connection or the shell is unresolvable, with its reason",
        arguments: [
            ("~/keys/%h", UnresolvableReason.connectionToken("%h")),
            ("/keys/%r@%h", .connectionToken("%r")),
            ("${HOME}/id", .environmentVariable),
            ("~bob/id", .otherUsersHome),
            ("id_ed25519", .relativePath),
            ("keys/id", .relativePath),
            ("/keys/trailing%", .connectionToken("%")),
        ]
    )
    func unresolvable(_ argument: String, _ reason: UnresolvableReason) {
        #expect(Self.resolve(argument) == .unresolvable(reason))
    }

    @Test("Tokens are expanded only in what the user wrote, after the tilde")
    func tildeComesFirst() {
        // A `%` in the home directory's own path would otherwise be read as a token.
        let context = IdentityResolutionContext(
            homeDirectory: URL(filePath: "/fabricated/100%home"),
            sshDirectory: SSHDirectory(url: URL(filePath: "/fabricated/keys")),
            userName: "alice",
            defaultDirectory: URL(filePath: "/fabricated/100%home/x")
        )
        #expect(
            IdentityFileResolver().resolve("~/id", in: context).resolution
                == .path(URL(filePath: "/fabricated/100%home/id"))
        )
    }
}
