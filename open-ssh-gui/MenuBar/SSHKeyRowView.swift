import SwiftUI

/// One key pair, as a row in the list.
///
/// Compact on purpose: the panel is 320 points wide and the list is bounded, so a row that
/// spelled out every attribute would show two keys where five fit. The detail a selected key
/// needs — its fingerprint, its paths, its actions — is presented below the list rather than
/// inside every row.
///
/// Declares no font, spacing or colour of its own: every value comes from the design system.
struct SSHKeyRowView: View {

    let pair: SSHKeyPair

    /// Whether this pair is the one an operation is running on, so the row can say so rather
    /// than appearing to have done nothing.
    let isOperating: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.snug) {
            Image(systemName: role.symbolName)
                .foregroundStyle(ColorRoleAppearance.style(for: role.colorRole))
                // The icon repeats what the text already says, so a screen reader should not
                // read it twice.
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(pair.displayName)
                    .font(Typography.control)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(pair.attributeSummary)
                    .font(Typography.fieldMessage)
                    .foregroundStyle(ColorRoleAppearance.style(for: .secondaryText))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.hairline)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The state is in the words as well as the icon's tint, so nothing here is conveyed
        // by colour alone.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pair.displayName). \(pair.attributeSummary). \(message)")
    }

    private var role: StatusRole {
        isOperating ? .inProgress : pair.statusRole
    }

    private var message: String {
        isOperating ? "Working…" : pair.statusMessage
    }
}

#Preview("A complete pair, one with no private key, and one that will not parse") {
    let directory = URL(filePath: "/preview/keys", directoryHint: .isDirectory)

    func pair(_ name: String, privateKey: Bool, parsed: Bool) -> SSHKeyPair {
        let key = SSHKeyName.discovered(name)!
        return SSHKeyPair(
            location: SSHKeyPairLocation(
                name: key,
                publicKeyURL: key.publicKeyURL(in: directory),
                privateKeyURL: privateKey ? key.privateKeyURL(in: directory) : nil,
                certificateURL: nil
            ),
            publicKey: parsed
                ? .success(
                    SSHPublicKey(
                        algorithm: .ed25519,
                        bitLength: 256,
                        fingerprint: SSHFingerprint(value: "SHA256:3Xq2wPl9kFzN0aBcDeFgHiJkLmNoPqRs"),
                        comment: "user@host"
                    )
                )
                : .failure(.malformedLine)
        )
    }

    return VStack(alignment: .leading, spacing: Spacing.snug) {
        SSHKeyRowView(pair: pair("id_ed25519", privateKey: true, parsed: true), isOperating: false)
        SSHKeyRowView(pair: pair("orphan", privateKey: false, parsed: true), isOperating: false)
        SSHKeyRowView(pair: pair("broken", privateKey: true, parsed: false), isOperating: false)
        SSHKeyRowView(pair: pair("id_rsa", privateKey: true, parsed: true), isOperating: true)
    }
    .padding(Spacing.loose)
    .frame(width: PanelMetrics.width)
}
