import Foundation
import Testing

/// The projection that lets the menu bar render a directory status through the design system's
/// status component. Lives beside the status enum rather than in the design system, so the design
/// system never learns what an SSH directory is.
@Suite("Directory status mapped onto the status vocabulary")
struct StatusRoleMappingTests {

    private static let directory = SSHDirectory(url: URL(filePath: "/fabricated/scratch"))
    private static let rejected = URL(filePath: "/fabricated/no-such-directory")

    @Test("An unsettled status is in progress, and says so")
    func resolvingIsInProgress() {
        let status = SSHDirectoryStatus.resolving

        #expect(status.statusRole == .inProgress)
        #expect(status.statusMessage.isEmpty == false)
    }

    @Test("A reachable directory is a success")
    func reachableIsSuccess() {
        let status = SSHDirectoryStatus.reachable(Self.directory)

        #expect(status.statusRole == .success)
        #expect(status.statusMessage == "Reachable")
    }

    @Test("A rejected override is a failure, because there is no directory at all")
    func unresolvedIsFailure() throws {
        let error = SSHDirectoryResolutionError.overridePathIsNotADirectory(Self.rejected)
        let status = SSHDirectoryStatus.unresolved(error)

        #expect(status.statusRole == .failure)
        #expect(status.statusMessage == error.reason)
    }

    @Test("An unreadable directory is a warning, because the directory exists and is fixable")
    func unreadableIsWarning() {
        let error = FileAccessError.accessDenied(Self.directory.url)
        let status = SSHDirectoryStatus.unreadable(Self.directory, error)

        #expect(status.statusRole == .warning)
        #expect(status.statusMessage == error.reason)
    }

    @Test("Every status carries a message, so the indicator is never blank")
    func everyStatusHasAMessage() {
        let all: [SSHDirectoryStatus] = [
            .resolving,
            .reachable(Self.directory),
            .unresolved(.overridePathIsNotADirectory(Self.rejected)),
            .unreadable(Self.directory, .accessDenied(Self.directory.url)),
        ]

        for status in all {
            #expect(status.statusMessage.isEmpty == false)
        }
    }
}
