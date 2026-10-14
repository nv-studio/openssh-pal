import Foundation

/// Writes a value so that OpenSSH reads back exactly that value.
///
/// A value is written bare unless something in it would be read differently: whitespace would
/// split it, a quote or backslash would be consumed, a leading `=` would be taken for the
/// separator and a leading `#` for a comment. Such a value is wrapped in double quotes with
/// backslashes and double quotes escaped — the escapes `argv_split` recognises inside quotes.
///
/// Pure.
nonisolated struct SSHConfigValueFormatter {

    init() {}

    func argument(for value: String) -> String {
        guard needsQuoting(value) else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }

    /// The `IdentityFile` value for a chosen key: tilde form in the default SSH directory, so
    /// the file stays portable between machines, and the absolute path of the private key
    /// otherwise, because a tilde path would point at the real directory instead of the
    /// override.
    func identityFileArgument(for name: SSHKeyName, context: IdentityResolutionContext) -> String {
        let path = context.isDefaultDirectory
            ? "~/" + SSHDirectoryResolver.directoryName + "/" + name.rawValue
            : name.privateKeyURL(in: context.sshDirectory.url).path(percentEncoded: false)
        return argument(for: path)
    }

    private func needsQuoting(_ value: String) -> Bool {
        value.isEmpty
            || value.hasPrefix("=")
            || value.hasPrefix("#")
            || value.contains { $0.isWhitespace || $0 == "'" || $0 == "\\" || $0 == "\"" }
    }
}
