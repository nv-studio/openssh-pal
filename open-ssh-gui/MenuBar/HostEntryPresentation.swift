import Foundation

/// Every string and symbol the host list renders for one entry.
///
/// Computed here, from values, so no view composes text and every word is testable without
/// rendering anything — the same reason `SSHKeyPair` carries its own presentation projections.
nonisolated struct HostEntryPresentation: Identifiable, Sendable, Equatable {

    let id: HostEntryID
    let title: String
    let summary: String

    /// One per `IdentityFile`, or "Default identities" when there are none.
    let keyTexts: [String]

    /// Where the entry is declared, relative to the SSH directory when inside it.
    let file: String

    let isPatternEntry: Bool

    /// Other concrete hosts using one of this entry's keys. Empty means no warning.
    let sharingHosts: [String]

    /// Why Edit and Delete are not offered, or `nil` where they are.
    let readOnlyReason: String?

    private let isDeclaredInConfig: Bool

    init(
        entry: HostEntry,
        associations: [KeyAssociation],
        sharingHosts: [String],
        file: String,
        isDeclaredInConfig: Bool
    ) {
        id = entry.id
        title = entry.displayName
        summary = Self.summary(of: entry)
        keyTexts = associations.isEmpty ? ["Default identities"] : associations.map(Self.text(for:))
        self.file = file
        isPatternEntry = entry.isPatternEntry
        self.sharingHosts = sharingHosts
        readOnlyReason = entry.writability.readOnlyReason
        self.isDeclaredInConfig = isDeclaredInConfig
    }

    var keySummary: String { keyTexts.joined(separator: ", ") }

    var isShared: Bool { !sharingHosts.isEmpty }

    var isReadOnly: Bool { readOnlyReason != nil }

    /// Named only when the entry is not in `config` itself, where the user would look first.
    var fileText: String? {
        isDeclaredInConfig ? nil : "Declared in \(file)"
    }

    var patternMarker: String? {
        isPatternEntry ? "Pattern" : nil
    }

    var sharingWarning: String? {
        isShared ? "Key shared with \(sharingHosts.joined(separator: ", "))" : nil
    }

    /// The warning symbol in the warning colour for a shared key — a symbol *and* a colour, so
    /// the warning is never conveyed by colour alone — and a neutral one otherwise.
    var symbolName: String {
        if isShared { return StatusRole.warning.symbolName }
        return isPatternEntry ? "asterisk.circle" : "server.rack"
    }

    var symbolColor: ColorRole {
        isShared ? .warning : .secondaryText
    }

    /// The row's second line.
    var detailLine: String {
        [summary, keySummary].joined(separator: " · ")
    }

    var accessibilityLabel: String {
        var parts = ["Host \(title)"]
        if let patternMarker { parts.append("\(patternMarker) entry") }
        parts.append(summary)
        parts.append("Key: \(keySummary)")
        if let fileText { parts.append(fileText) }
        if isShared { parts.append("Warning: key shared with \(sharingHosts.joined(separator: ", "))") }
        if isReadOnly { parts.append("Read-only") }
        return parts.joined(separator: ". ")
    }

    // MARK: - Text

    private static func summary(of entry: HostEntry) -> String {
        if let hostName = entry.hostName?.value {
            let user = entry.user.map { "\($0.value)@" } ?? ""
            let port = entry.port.map { ":\($0.value)" } ?? ""
            return user + hostName + port
        }

        let parts = [entry.user.map { "User \($0.value)" }, entry.port.map { "Port \($0.value)" }].compactMap(\.self)
        return parts.isEmpty ? "No HostName, User or Port declared" : parts.joined(separator: ", ")
    }

    private static func text(for association: KeyAssociation) -> String {
        switch association {
        case .listed(let name): name.rawValue
        case .unlisted(let raw): "\(raw) (not a listed key)"
        case .unresolved(let raw, let reason): "\(raw) (unresolved: \(reason.description))"
        case .disabled: "IdentityFile none"
        }
    }
}
