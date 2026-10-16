import Foundation
import Testing

@Suite("Resolved directory value and the typed error vocabulary")
struct SSHDirectoryTests {

    @Test("A resolved directory exposes the URL it was resolved to")
    func resolvedDirectoryExposesItsURL() {
        let url = URL(filePath: "/fabricated/scratch", directoryHint: .isDirectory)

        #expect(SSHDirectory(url: url).url == url)
    }

    @Test("Two resolved directories at the same URL are equal")
    func resolvedDirectoriesAreValues() {
        let url = URL(filePath: "/fabricated/scratch", directoryHint: .isDirectory)

        #expect(SSHDirectory(url: url) == SSHDirectory(url: url))
    }

    @Test(
        "Every resolution error names the offending path and gives a reason",
        arguments: [
            SSHDirectoryResolutionError.overridePathDoesNotExist(Self.offender),
            SSHDirectoryResolutionError.overridePathIsNotADirectory(Self.offender),
        ]
    )
    func resolutionErrorsCarryTheOffendingPath(_ error: SSHDirectoryResolutionError) {
        #expect(error.url == Self.offender)
        #expect(error.reason.contains(Self.offender.path(percentEncoded: false)))
    }

    @Test(
        "Every file-access error names the path it refers to and gives a reason",
        arguments: [
            FileAccessError.directoryNotFound(Self.offender),
            FileAccessError.accessDenied(Self.offender),
            FileAccessError.unreadable(Self.offender),
        ]
    )
    func fileAccessErrorsCarryTheirPath(_ error: FileAccessError) {
        #expect(error.url == Self.offender)
        #expect(error.reason.contains(Self.offender.path(percentEncoded: false)))
    }

    @Test("Absence and permission denial are distinguishable")
    func absenceAndDenialAreDistinct() {
        #expect(FileAccessError.directoryNotFound(Self.offender) != .accessDenied(Self.offender))
    }

    private static let offender = URL(filePath: "/fabricated/no-such-directory", directoryHint: .isDirectory)
}
