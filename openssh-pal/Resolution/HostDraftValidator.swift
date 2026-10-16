import Foundation

/// Judges every value of a host form before anything is written.
///
/// Each field is judged on its own and every rejection is reported at once, keyed by field, so
/// the form can show each message beside the value it concerns.
///
/// Characters that only need quoting — a backslash, a single quote — are accepted: the
/// formatter quotes them so the written line reads back as the typed value. Only what no
/// quoting can carry, or what would change what the line means, is rejected.
///
/// Pure.
nonisolated struct HostDraftValidator {

    init() {}

    func validate(
        _ draft: HostDraft,
        mode: HostFormMode,
        existing: [HostEntry]
    ) -> Result<ValidatedHostDraft, HostDraftErrors> {
        var errors: [HostDraftField: HostDraftError] = [:]

        let patterns = validatePatterns(draft.patterns, mode: mode, existing: existing)
        let hostName = validateWord(draft.hostName)
        let user = validateWord(draft.user)
        let port = validatePort(draft.port)

        if case .failure(let error) = patterns { errors[.patterns] = error }
        if case .failure(let error) = hostName { errors[.hostName] = error }
        if case .failure(let error) = user { errors[.user] = error }
        if case .failure(let error) = port { errors[.port] = error }

        guard errors.isEmpty,
              case .success(let validPatterns) = patterns,
              case .success(let validHostName) = hostName,
              case .success(let validUser) = user,
              case .success(let validPort) = port
        else {
            return .failure(HostDraftErrors(byField: errors))
        }

        return .success(
            ValidatedHostDraft(
                patterns: validPatterns,
                hostName: validHostName,
                user: validUser,
                port: validPort,
                keyChoice: draft.keyChoice
            )
        )
    }

    // MARK: - Patterns

    private func validatePatterns(
        _ text: String,
        mode: HostFormMode,
        existing: [HostEntry]
    ) -> Result<[String], HostDraftError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        if let character = forbiddenCharacter(in: text) { return .failure(.forbiddenCharacter(character)) }

        let tokens: [String]
        let declared: Set<String>

        switch mode {
        case .create:
            guard !trimmed.contains(where: \.isWhitespace) else { return .failure(.notASingleConcreteHost) }
            tokens = [trimmed]
            declared = []
        case .edit(let entry):
            tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            declared = Set(entry.patterns.map(\.token))
        }

        // A pattern the block already declares is kept as it is; only what the user adds has to
        // be a single concrete host.
        let added = tokens.filter { !declared.contains($0) }
        if added.contains(where: { HostPattern(parsing: $0).isNegated || HostPattern(parsing: $0).hasWildcard }) {
            return .failure(.notASingleConcreteHost)
        }

        let others = existing.filter { !$0.isPatternEntry && $0.id != mode.editedEntry?.id }
        for token in added {
            if let duplicate = others.first(where: { declaresConcretePattern(token, $0) }) {
                return .failure(.duplicatesHost(duplicate.displayName))
            }
        }

        return .success(tokens)
    }

    /// Whether `entry` already names `alias` as one of its own concrete patterns. Compared
    /// lowercased, because `ssh` lowercases the host name it matches.
    private func declaresConcretePattern(_ alias: String, _ entry: HostEntry) -> Bool {
        let alias = alias.lowercased()
        return entry.patterns.contains { !$0.isNegated && !$0.hasWildcard && $0.text.lowercased() == alias }
    }

    // MARK: - Values

    /// A host name or a user: optional, and a single word.
    private func validateWord(_ text: String) -> Result<String?, HostDraftError> {
        if let character = forbiddenCharacter(in: text) { return .failure(.forbiddenCharacter(character)) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(nil) }
        guard !trimmed.contains(where: \.isWhitespace) else { return .failure(.containsWhitespace) }
        return .success(trimmed)
    }

    private func validatePort(_ text: String) -> Result<String?, HostDraftError> {
        if let character = forbiddenCharacter(in: text) { return .failure(.forbiddenCharacter(character)) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(nil) }

        // Digits only: `Int("+22")` would accept a sign `ssh` does not.
        guard trimmed.allSatisfy(\.isASCII), trimmed.allSatisfy(\.isNumber),
              let port = Int(trimmed), (1...65535).contains(port)
        else { return .failure(.portOutOfRange) }

        return .success(String(port))
    }

    /// The first character no configuration value may contain: a line break would end the
    /// directive, a `#` may start a comment, and a double quote would change how the rest of
    /// the line is split.
    private func forbiddenCharacter(in text: String) -> HostDraftError.ForbiddenCharacter? {
        if text.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" }) { return .lineBreak }
        if text.contains("#") { return .hash }
        if text.contains("\"") { return .doubleQuote }
        return nil
    }
}
