import Foundation

/// What the user asked for, as the generator receives it.
///
/// The passphrase is deliberately **not** a field. It travels as a separate argument to
/// `generate`, so there is no value in the app that carries both a request and a secret —
/// and nothing that could serialise or describe the two together.
///
/// The request also owns the whole `ssh-keygen` argument list. Keeping it here rather than in
/// the adapter means the one assertion that matters most — that no secret is in the arguments
/// — can be made without launching a process.
nonisolated struct SSHKeyGenerationRequest: Equatable, Sendable {

    let name: SSHKeyName
    let type: SSHKeyType

    /// The `-C` comment. Empty is allowed; `ssh-keygen` writes an empty comment field.
    let comment: String

    init(name: SSHKeyName, type: SSHKeyType, comment: String) {
        self.name = name
        self.type = type
        self.comment = comment
    }

    /// The complete argument list, for a key written into `directory`.
    ///
    /// `-N` and `-P` are absent and must stay absent: either would put the passphrase in the
    /// argument list, where any process listing would show it. The passphrase goes in on
    /// standard input instead.
    func keygenArguments(in directory: URL) -> [String] {
        type.keygenArguments + [
            "-C", comment,
            "-f", name.privateKeyURL(in: directory).path(percentEncoded: false),
        ]
    }
}
