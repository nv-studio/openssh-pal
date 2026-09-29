import Foundation

/// A directory that resolution has accepted as *the* SSH directory for this launch.
///
/// The wrapper exists so a validated directory is distinguishable in the type system from
/// an arbitrary `URL`; nothing but `SSHDirectoryResolver` should construct one.
struct SSHDirectory: Sendable, Equatable {
    let url: URL

    init(url: URL) {
        self.url = url
    }
}
