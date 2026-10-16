import Foundation

/// A `HostReferenceLookup` that answers every key with one fixed report, and records which
/// keys it was asked about.
///
/// Fixed rather than computed, so a key list test states exactly what the configuration says
/// and asserts only how key management presents it.
@MainActor
final class StaticHostReferenceLookup: HostReferenceLookup {

    let report: HostReferenceReport
    private(set) var askedAbout: [SSHKeyName] = []

    init(report: HostReferenceReport) {
        self.report = report
    }

    func hostReferences(to pair: SSHKeyPair) -> HostReferenceReport {
        askedAbout.append(pair.id)
        return report
    }
}
