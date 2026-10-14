import Foundation

/// Expands the configuration tokens that need no connection: `%d`, `%u` and `%%`.
///
/// Shared by `Include` and `IdentityFile`, which accept the same tokens, so the two cannot
/// disagree about what the app is willing to resolve. Anything else — a per-connection token
/// such as `%h`, or a `${VARIABLE}` — is reported rather than guessed at.
///
/// Pure.
nonisolated struct ConfigTokenExpander {

    init() {}

    func expand(_ text: String, in context: IdentityResolutionContext) -> Result<String, UnresolvableReason> {
        var result = ""
        var scalars = text.unicodeScalars.makeIterator()
        var pending = scalars.next()

        while let scalar = pending {
            pending = scalars.next()

            switch scalar {
            case "%":
                guard let token = pending else { return .failure(.connectionToken("%")) }
                pending = scalars.next()
                switch token {
                case "%": result += "%"
                case "d": result += IdentityResolutionContext.normalizedPath(of: context.homeDirectory)
                case "u": result += context.userName
                default: return .failure(.connectionToken("%" + String(token)))
                }
            case "$" where pending == "{":
                return .failure(.environmentVariable)
            default:
                result.unicodeScalars.append(scalar)
            }
        }

        return .success(result)
    }
}
