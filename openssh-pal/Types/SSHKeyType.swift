import Foundation

/// A key type carrying exactly the parameters that apply to it.
///
/// The parameters are associated values rather than optional properties, so `.ed25519`
/// holding a bit length — or `.rsa` holding a curve — is a compile error rather than
/// something a validator has to catch. There is no combination of this type that
/// `ssh-keygen` would reject.
///
/// The type also owns the `ssh-keygen` spelling for each case. No call site assembles
/// flags, so a new key type is added here and nowhere else.
nonisolated enum SSHKeyType: Equatable, Hashable, Sendable, CaseIterable {
    case ed25519
    case rsa(RSAKeyLength)
    case ecdsa(ECDSACurve)

    /// What OpenSSH recommends, and therefore what the create form starts on.
    static let `default`: SSHKeyType = .ed25519

    /// Every type-and-parameter combination the generator accepts.
    ///
    /// Written out rather than synthesized, because Swift cannot derive `CaseIterable` for
    /// an enum with associated values. Composing it from the parameter enums is what keeps
    /// the list correct when a length or a curve is added.
    static var allCases: [SSHKeyType] {
        [.ed25519]
            + RSAKeyLength.allCases.map(SSHKeyType.rsa)
            + ECDSACurve.allCases.map(SSHKeyType.ecdsa)
    }

    /// What `-t` names this type on the command line.
    var keygenTypeName: String {
        switch self {
        case .ed25519: "ed25519"
        case .rsa: "rsa"
        case .ecdsa: "ecdsa"
        }
    }

    /// The arguments that select this type and its parameters.
    var keygenArguments: [String] {
        switch self {
        case .ed25519:
            ["-t", keygenTypeName]
        case .rsa(let length):
            ["-t", keygenTypeName, "-b", String(length.rawValue)]
        case .ecdsa(let curve):
            ["-t", keygenTypeName, "-b", String(curve.rawValue)]
        }
    }

    /// The bit length a key of this type reports once generated.
    ///
    /// This is what the acceptance gate compares against the key `ssh-keygen` actually
    /// wrote, so a tool that produced the wrong type is caught rather than accepted.
    var expectedBitLength: Int {
        switch self {
        case .ed25519:
            // Fixed by the curve: Ed25519 takes no size parameter and always reports 256.
            256
        case .rsa(let length):
            length.rawValue
        case .ecdsa(let curve):
            curve.rawValue
        }
    }

    /// The family this type belongs to, so a form can present the choice in two steps.
    var family: SSHKeyTypeFamily {
        switch self {
        case .ed25519: .ed25519
        case .rsa: .rsa
        case .ecdsa: .ecdsa
        }
    }
}

/// The key type choice a user makes before choosing a parameter.
///
/// Separate from `SSHKeyType` because the form offers three types (8.3) while the type
/// itself enumerates seven combinations. Each family proposes a type, so switching family
/// can never leave the selection without a parameter.
nonisolated enum SSHKeyTypeFamily: Equatable, Hashable, Sendable, CaseIterable {
    case ed25519
    case rsa
    case ecdsa

    /// How the family is named to the user.
    ///
    /// Held on the value rather than written at a call site, so the form enumerates nothing
    /// and a new family is named in one place.
    var displayName: String {
        switch self {
        case .ed25519: "Ed25519"
        case .rsa: "RSA"
        case .ecdsa: "ECDSA"
        }
    }

    /// The type selecting this family produces, before the user adjusts its parameter.
    var defaultType: SSHKeyType {
        switch self {
        case .ed25519: .ed25519
        case .rsa: .rsa(.bits4096)
        case .ecdsa: .ecdsa(.nistp256)
        }
    }
}

/// The RSA modulus sizes offered. 1024 is absent deliberately: it is no longer considered
/// adequate and offering it would invite a weak key.
nonisolated enum RSAKeyLength: Int, Equatable, Hashable, Sendable, CaseIterable {
    case bits2048 = 2048
    case bits3072 = 3072
    case bits4096 = 4096

    var displayName: String { "\(rawValue) bits" }
}

/// The three NIST curves `ssh-keygen` accepts for ECDSA, named by the bit length that
/// selects them on the command line.
nonisolated enum ECDSACurve: Int, Equatable, Hashable, Sendable, CaseIterable {
    case nistp256 = 256
    case nistp384 = 384
    case nistp521 = 521

    /// Named as OpenSSH names the curve, not as a bit count: `nistp521` is the spelling a
    /// user will recognise from `ssh-keygen -l`.
    var displayName: String { "nistp\(rawValue)" }
}
