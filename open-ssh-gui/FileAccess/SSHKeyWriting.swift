import Foundation

/// The only port through which this application mutates a file.
///
/// **Move and remove. There is no create.** The only code path that brings a file into
/// existence anywhere in the app is `ssh-keygen` itself, which is what makes "defer to
/// OpenSSH" a property of the type system rather than a convention someone has to remember.
///
/// This is a *separate* port from `SSHDirectoryReading`, which is not widened: a component
/// holding only the read port still cannot change anything, and a component holding only
/// this one cannot read a private key.
///
/// Each method is one file operation. All-or-nothing semantics across several files belong to
/// the planners and the model, so that the adapter has no logic to get wrong.
///
/// `Sendable` so a `nonisolated` conformer can be stored by a `@MainActor` consumer.
protocol SSHKeyWriting: Sendable {

    /// Moves one file, preserving its permissions, and never replacing an existing
    /// destination.
    ///
    /// Refusing an existing destination is a backstop beneath name validation, not a
    /// substitute for it: even a defective validator cannot destroy a bystander file through
    /// this call.
    func move(from source: URL, to destination: URL) async throws(SSHKeyWriteError)

    /// Removes exactly one file. Irreversible — there is no Trash and no undo.
    func remove(at url: URL) async throws(SSHKeyWriteError)
}
