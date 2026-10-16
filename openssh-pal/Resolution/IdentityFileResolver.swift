import Foundation

/// Resolves an `IdentityFile` value as far as it can be without a connection.
///
/// Follows `ssh`'s order: tilde first, then tokens. `~/`, `%d`, `%u` and `%%` resolve; `none`
/// disables identity files. Everything else — a per-connection token, an environment variable,
/// another user's home, a relative path — is reported with its reason and never guessed at.
///
/// Paths are standardised but symbolic links are **not** resolved: key discovery does not
/// resolve them either, and both sides have to compare the same way.
///
/// Pure.
nonisolated struct IdentityFileResolver {

    /// The value that turns identity files off.
    static let disabledValue = "none"

    private let tokens = ConfigTokenExpander()

    init() {}

    func resolve(_ argument: String, in context: IdentityResolutionContext) -> IdentityReference {
        IdentityReference(raw: argument, resolution: resolution(of: argument, in: context))
    }

    private func resolution(of argument: String, in context: IdentityResolutionContext) -> IdentityReference.Resolution {
        guard argument != Self.disabledValue else { return .disabled }

        var base = ""
        var remainder = argument

        if argument.hasPrefix("~") {
            let afterTilde = argument.dropFirst()
            guard afterTilde.isEmpty || afterTilde.hasPrefix("/") else { return .unresolvable(.otherUsersHome) }
            base = IdentityResolutionContext.normalizedPath(of: context.homeDirectory)
            remainder = String(afterTilde)
        }

        switch tokens.expand(remainder, in: context) {
        case .failure(let reason):
            return .unresolvable(reason)
        case .success(let expanded):
            let path = base + expanded
            // `ssh` resolves a relative path against its own working directory, which the app
            // cannot know.
            guard path.hasPrefix("/") else { return .unresolvable(.relativePath) }
            return .path(URL(filePath: path).standardizedFileURL)
        }
    }
}
