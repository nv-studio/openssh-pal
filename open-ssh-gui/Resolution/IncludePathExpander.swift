import Foundation

/// Anchors and expands one `Include` argument into an absolute glob path.
///
/// Follows `readconf.c`: a path that is neither absolute nor `~`-prefixed is anchored at the
/// SSH directory — here, the *resolved* one, which is identical to `ssh` in the default case
/// and keeps an override self-contained otherwise. Then tokens are expanded.
///
/// Under an override, a path outside the override directory is skipped rather than read. `~`
/// always expands to the real home directory, which therefore lands outside an override and is
/// skipped: a test launch can never read the developer's own configuration this way.
///
/// Pure.
nonisolated struct IncludePathExpander {

    private let tokens = ConfigTokenExpander()

    init() {}

    func expand(_ argument: String, in context: IdentityResolutionContext) -> Result<GlobPath, SkippedIncludeReason> {
        let base: String
        let remainder: String

        if argument.hasPrefix("~") {
            let afterTilde = argument.dropFirst()
            guard afterTilde.isEmpty || afterTilde.hasPrefix("/") else {
                return .failure(.unresolvable(.otherUsersHome))
            }
            base = IdentityResolutionContext.normalizedPath(of: context.homeDirectory)
            remainder = String(afterTilde)
        } else if argument.hasPrefix("/") {
            base = ""
            remainder = argument
        } else {
            base = IdentityResolutionContext.normalizedPath(of: context.sshDirectory.url)
            remainder = "/" + argument
        }

        // Tokens are expanded in what the user wrote only, never in the home or SSH directory's
        // own path, where a `%` is just a character.
        let expanded: String
        switch tokens.expand(remainder, in: context) {
        case .success(let text): expanded = text
        case .failure(let reason): return .failure(.unresolvable(reason))
        }

        let location = URL(filePath: base + expanded)
        if !context.isDefaultDirectory, !context.contains(location) {
            return .failure(.outsideOverride)
        }
        return .success(GlobPath(path: IdentityResolutionContext.normalizedPath(of: location)))
    }
}
