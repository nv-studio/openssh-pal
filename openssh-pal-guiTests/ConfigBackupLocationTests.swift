import Foundation
import Testing

/// A backup beside a config file is only safe if `ssh` will never read it. A dotfile is skipped
/// by `*`, but not by an `Include` that matches dotfiles — and then the backup would become a
/// second copy of every host in it.
@Suite("Config backup location")
nonisolated struct ConfigBackupLocationTests {

    private static let file = URL(filePath: "/fabricated/keys/config.d/work")

    @Test("The backup is a hidden file beside the original")
    func hiddenBesideTheFile() {
        let result = ConfigBackupLocation().backupURL(for: Self.file, avoiding: [])
        #expect(result == .success(URL(filePath: "/fabricated/keys/config.d/.work.openssh-pal-backup")))
    }

    @Test("An include that matches ordinary names does not match the hidden backup")
    func ordinaryGlobsDoNotMatch() {
        let includes = [GlobPath(path: "/fabricated/keys/config.d/*"), GlobPath(path: "/fabricated/keys/*/*")]
        #expect((try? ConfigBackupLocation().backupURL(for: Self.file, avoiding: includes).get()) != nil)
    }

    @Test("An include that matches every dotfile refuses the backup, naming the pattern")
    func dotGlobRefuses() {
        let includes = [GlobPath(path: "/fabricated/keys/config.d/.*")]
        #expect(
            ConfigBackupLocation().backupURL(for: Self.file, avoiding: includes)
                == .failure(.matchedByInclude("/fabricated/keys/config.d/.*"))
        )
    }

    @Test("An include of the exact backup path refuses it; one in another directory does not")
    func exactAndElsewhere() {
        let exact = [GlobPath(path: "/fabricated/keys/config.d/.work.openssh-pal-backup")]
        #expect((try? ConfigBackupLocation().backupURL(for: Self.file, avoiding: exact).get()) == nil)

        let elsewhere = [GlobPath(path: "/fabricated/other/.*")]
        #expect((try? ConfigBackupLocation().backupURL(for: Self.file, avoiding: elsewhere).get()) != nil)
    }
}
