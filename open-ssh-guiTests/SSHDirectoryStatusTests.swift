import Foundation
import Testing

/// The projection the menu bar renders. Keeping it here rather than in the view is what lets
/// the view hold no logic.
@Suite("What the menu bar shows for each status")
struct SSHDirectoryStatusTests {

    private static let directory = SSHDirectory(url: URL(filePath: "/fabricated/scratch"))
    private static let rejected = URL(filePath: "/fabricated/no-such-directory")

    @Test("While resolving there is no path, no reachability and nothing to explain")
    func resolvingShowsNothingYet() {
        let status = SSHDirectoryStatus.resolving

        #expect(status.displayPath == nil)
        #expect(status.isReachable == false)
        #expect(status.failureReason == nil)
    }

    @Test("A reachable directory shows its path and no failure reason")
    func reachableShowsPathOnly() {
        let status = SSHDirectoryStatus.reachable(Self.directory)

        #expect(status.displayPath == "/fabricated/scratch")
        #expect(status.isReachable)
        #expect(status.failureReason == nil)
    }

    @Test("An unreadable directory shows its path alongside the reason, and is not reachable")
    func unreadableShowsPathAndReason() {
        let status = SSHDirectoryStatus.unreadable(Self.directory, .accessDenied(Self.directory.url))

        #expect(status.displayPath == "/fabricated/scratch")
        #expect(status.isReachable == false)
        #expect(status.failureReason == FileAccessError.accessDenied(Self.directory.url).reason)
    }

    @Test("An unresolved directory names the path the override was rejected for")
    func unresolvedNamesTheOffendingPath() throws {
        let status = SSHDirectoryStatus.unresolved(.overridePathDoesNotExist(Self.rejected))

        #expect(status.displayPath == "/fabricated/no-such-directory")
        #expect(status.isReachable == false)
        #expect(try #require(status.failureReason).contains("/fabricated/no-such-directory"))
    }

    @Test("Only the reachable case reports reachability")
    func onlyReachableIsReachable() {
        let others: [SSHDirectoryStatus] = [
            .resolving,
            .unresolved(.overridePathIsNotADirectory(Self.rejected)),
            .unreadable(Self.directory, .directoryNotFound(Self.directory.url)),
        ]

        #expect(others.allSatisfy { $0.isReachable == false })
    }
}
