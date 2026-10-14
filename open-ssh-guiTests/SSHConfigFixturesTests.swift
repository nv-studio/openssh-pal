import Foundation
import Testing

/// The corpus is only worth sharing if it covers what it claims to.
@Suite("Configuration fixture corpus")
nonisolated struct SSHConfigFixturesTests {

    @Test("Every fixture is listed once, under a distinct name")
    func everyFixtureIsEnumerated() {
        let names = SSHConfigFixtures.all.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.count >= 18)
    }

    @Test("The byte-level shapes are really present in the bytes")
    func byteLevelShapes() {
        #expect(SSHConfigFixtures.crlf.data.contains(Data([0x0D, 0x0A])))
        #expect(SSHConfigFixtures.noFinalNewline.data.last != 0x0A)
        #expect(SSHConfigFixtures.byteOrderMark.data.starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(SSHConfigFixtures.tabs.text.contains("\t"))
        #expect(SSHConfigFixtures.nonASCII.data.contains { $0 > 0x7F })
    }

    @Test("No fixture names a home directory or a literal SSH directory path")
    func fixturesNameNoRealDirectory() {
        for fixture in SSHConfigFixtures.all {
            #expect(!fixture.text.contains("/Users/"), "\(fixture.name)")
            #expect(!fixture.text.contains("~/" + SSHDirectoryResolver.directoryName), "\(fixture.name)")
        }
    }
}
