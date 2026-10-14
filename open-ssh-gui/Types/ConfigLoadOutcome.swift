import Foundation

/// What reading the configuration produced.
///
/// "No file" and "could not read the file" are separate cases because telling a user they have
/// no hosts when the app could not look would be worse than saying nothing.
nonisolated enum ConfigLoadOutcome: Sendable, Equatable {
    case noConfigFile
    case loaded(SSHConfiguration)

    /// `config` exists but could not be read. Problems with included files are issues inside
    /// `loaded` instead, because the rest of the configuration is still worth presenting.
    case unreadable(FileAccessError)
}
