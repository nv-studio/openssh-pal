import Foundation
import Testing

/// An `Include` argument is anchored and expanded before anything is read. Under an override
/// directory, anything that lands outside it is skipped — that is what keeps a test launch from
/// reading the developer's real configuration through `Include ~/…`.
@Suite("Include path expander")
nonisolated struct IncludePathExpanderTests {

    private static let home = URL(filePath: "/fabricated/home")
    private static let defaultDirectory = home.appending(path: SSHDirectoryResolver.directoryName)
    private static let override = URL(filePath: "/fabricated/keys")

    private static func context(_ directory: URL) -> IdentityResolutionContext {
        IdentityResolutionContext(
            homeDirectory: home,
            sshDirectory: SSHDirectory(url: directory),
            userName: "alice",
            defaultDirectory: defaultDirectory
        )
    }

    private static func expand(_ argument: String, in directory: URL = defaultDirectory) -> Result<GlobPath, SkippedIncludeReason> {
        IncludePathExpander().expand(argument, in: context(directory))
    }

    private static func path(_ argument: String, in directory: URL = defaultDirectory) -> String? {
        try? expand(argument, in: directory).get().path
    }

    @Test("A relative path is anchored at the resolved SSH directory")
    func relativeIsAnchored() {
        let directory = Self.defaultDirectory.path(percentEncoded: false)
        #expect(Self.path("config.d/*") == directory + "/config.d/*")
        #expect(Self.path("work", in: Self.override) == "/fabricated/keys/work")
    }

    @Test("Tilde expands to the home directory")
    func tilde() {
        #expect(Self.path("~/shared/ssh") == "/fabricated/home/shared/ssh")
        #expect(Self.path("~") == "/fabricated/home")
    }

    @Test("An absolute path is used as written")
    func absolute() {
        #expect(Self.path("/etc/ssh/ssh_config.d/*.conf") == "/etc/ssh/ssh_config.d/*.conf")
    }

    @Test("%d, %u and %% expand; dot segments are removed")
    func tokens() {
        #expect(Self.path("/srv/%u/config") == "/srv/alice/config")
        #expect(Self.path("/srv/100%%") == "/srv/100%")
        #expect(Self.path("~/%u") == "/fabricated/home/alice")
        #expect(Self.path("/srv/%d") == "/srv/fabricated/home")
        #expect(Self.path("/srv/a/../b") == "/srv/b")
    }

    @Test("A token, a variable or another user's home is reported rather than guessed at")
    func unresolvable() {
        #expect(Self.expand("/srv/%h") == .failure(.unresolvable(.connectionToken("%h"))))
        #expect(Self.expand("${HOME}/x") == .failure(.unresolvable(.environmentVariable)))
        #expect(Self.expand("~bob/config") == .failure(.unresolvable(.otherUsersHome)))
    }

    @Test("Under an override, a path outside it is skipped, however it is spelled")
    func overrideConfinement() {
        #expect(Self.expand("/fabricated/elsewhere/config", in: Self.override) == .failure(.outsideOverride))
        #expect(Self.expand("~/config", in: Self.override) == .failure(.outsideOverride))
        #expect(Self.expand("../escape", in: Self.override) == .failure(.outsideOverride))
        #expect(Self.path("sub/*", in: Self.override) == "/fabricated/keys/sub/*")
    }

    @Test("In the default directory, a system path may be read")
    func defaultDirectoryIsNotConfined() {
        #expect(Self.path("/etc/ssh/extra") == "/etc/ssh/extra")
    }
}
