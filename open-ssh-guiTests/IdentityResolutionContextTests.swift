import Foundation
import Testing

/// The default-directory projection decides whether an `IdentityFile` is written in tilde form
/// and whether include confinement applies, so it must not be fooled by spelling.
@Suite("Identity resolution context")
nonisolated struct IdentityResolutionContextTests {

    private static let home = URL(filePath: "/fabricated/home", directoryHint: .isDirectory)
    private static let defaultDirectory = home.appending(path: SSHDirectoryResolver.directoryName)

    private static func context(_ directory: URL) -> IdentityResolutionContext {
        IdentityResolutionContext(
            homeDirectory: home,
            sshDirectory: SSHDirectory(url: directory),
            userName: "alice",
            defaultDirectory: defaultDirectory
        )
    }

    @Test("The directory the resolver would choose without an override is the default one")
    func defaultDirectoryIsDefault() {
        #expect(Self.context(Self.defaultDirectory).isDefaultDirectory)
    }

    @Test("A trailing slash or a dot segment does not hide the default directory")
    func spellingDoesNotMatter() {
        #expect(Self.context(URL(filePath: Self.defaultDirectory.path(percentEncoded: false) + "/")).isDefaultDirectory)
        #expect(Self.context(Self.home.appending(path: "x/../" + SSHDirectoryResolver.directoryName)).isDefaultDirectory)
    }

    @Test("An override directory is not the default one")
    func overrideIsNotDefault() {
        #expect(!Self.context(URL(filePath: "/fabricated/keys")).isDefaultDirectory)
    }

    @Test("Containment is by path segment, so a sibling sharing a prefix is outside")
    func containment() {
        let context = Self.context(URL(filePath: "/fabricated/keys"))

        #expect(context.contains(URL(filePath: "/fabricated/keys/config")))
        #expect(context.contains(URL(filePath: "/fabricated/keys/config.d/work")))
        #expect(!context.contains(URL(filePath: "/fabricated/keys-other/config")))
        #expect(!context.contains(URL(filePath: "/fabricated/keys/../elsewhere")))
        #expect(!context.contains(URL(filePath: "/fabricated/keys")))
    }
}
