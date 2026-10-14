import Foundation
import Testing

/// The controls that keep this suite away from the developer's own SSH directory.
///
/// These are safety controls rather than hygiene, and the reason they are tests is that each
/// of them has already been described in `tech.md` and could still be undone by a plausible,
/// well-meaning change — adding a host application to get a UI test to run, or reaching for
/// the home directory in a fixture.
@Suite("Test isolation controls")
nonisolated struct TestIsolationTests {

    // The remaining control — that the test target has no host application — cannot be
    // asserted from here: the test process is not permitted to read inside the `.xcodeproj`
    // bundle, which fails with EPERM rather than with a useful answer. It is verified by
    // inspecting `project.pbxproj` for `TEST_HOST` and `BUNDLE_LOADER`, neither of which
    // appears in it.

    @Test("No test source reaches for the user's home directory")
    func noTestReachesForTheHomeDirectory() throws {
        // Spelled in pieces: written whole, this list is itself a test source naming both
        // symbols, and the check failed on its own file.
        let forbidden = ["NSHome" + "Directory", "homeDirectory" + "ForCurrentUser"]

        for source in try ProjectSources.tests() {
            for symbol in forbidden {
                #expect(
                    !source.text.contains(symbol),
                    "\(source.relativePath) reaches for the home directory: \(source.lines(containing: symbol))"
                )
            }
        }
    }

    @Test("No test source spells the SSH directory's name, which the resolver owns")
    func noTestSpellsTheSSHDirectoryName() throws {
        // `SSHDirectoryResolver.directoryName` is the one place that string lives. A test
        // that spelled it itself would still pass if the resolver changed, and would be
        // pointing at a real directory while it did.
        for source in try ProjectSources.tests() {
            #expect(
                !source.text.contains("\".ssh\""),
                "\(source.relativePath) spells the SSH directory name as a literal"
            )
        }
    }

    @Test("No test string literal spells a tilde path into the SSH directory")
    func noTestSpellsTheTildeSSHPath() throws {
        // A configuration fixture with this path would read as the developer's own directory
        // to anyone resolving it. Tests build it from the resolver's constant instead. Only a
        // literal is matched — prose in a comment naming the directory is not a path.
        let tildePath = "\"~/" + "." + "ssh"
        for source in try ProjectSources.tests() {
            #expect(
                !source.text.contains(tildePath),
                "\(source.relativePath) spells \(tildePath): \(source.lines(containing: tildePath))"
            )
        }
    }

    @Test("Only the composition root asks the process for anything")
    func onlyTheRootReadsTheProcess() throws {
        // The launch environment is a value so that every rule above it is testable without
        // the real process. This fails if something below the root starts reading it again.
        for source in try ProjectSources.application() {
            guard source.text.contains(".processInfo") else { continue }
            #expect(
                source.relativePath == "open-ssh-gui/OpenSSHGUIApp.swift"
                    || source.isIn("open-ssh-gui/Platform"),
                "\(source.relativePath) reads ProcessInfo outside the composition root"
            )
        }
    }
}
