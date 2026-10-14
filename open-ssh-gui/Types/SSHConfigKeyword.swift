import Foundation

/// A configuration keyword, compared as OpenSSH compares it: without regard to case.
///
/// Only the lowercased form is held. The spelling the user wrote stays in the line's raw text,
/// which is the only place it is needed — an edit keeps the keyword exactly as written by never
/// rewriting it.
nonisolated struct SSHConfigKeyword: Hashable, Sendable {

    /// The keyword lowercased, as `readconf.c` lowercases it before looking it up.
    let name: String

    init(_ spelling: String) {
        name = spelling.lowercased()
    }

    static let host = SSHConfigKeyword("Host")
    static let match = SSHConfigKeyword("Match")
    static let include = SSHConfigKeyword("Include")
    static let hostName = SSHConfigKeyword("HostName")
    static let user = SSHConfigKeyword("User")
    static let port = SSHConfigKeyword("Port")
    static let identityFile = SSHConfigKeyword("IdentityFile")
}
