import Foundation

/// A public key's algorithm, named as OpenSSH names it on the wire.
///
/// The `other` case is what keeps parsing total. `~/.ssh` may hold a security-key or
/// certificate algorithm this app has never heard of, and an unknown spelling is still a
/// fact worth presenting — dropping the entry or trapping on it would be worse than showing
/// the name OpenSSH wrote.
nonisolated enum SSHKeyAlgorithm: Equatable, Hashable, Sendable {
    case ed25519
    case rsa
    case dsa
    case ecdsa(ECDSACurve)
    case other(String)

    /// The spelling that appears inside the key blob.
    var wireName: String {
        switch self {
        case .ed25519: "ssh-ed25519"
        case .rsa: "ssh-rsa"
        case .dsa: "ssh-dss"
        case .ecdsa(let curve): "ecdsa-sha2-nistp\(curve.rawValue)"
        case .other(let name): name
        }
    }

    /// How the algorithm is named to the user.
    ///
    /// An unrecognised algorithm is shown by its wire name: that is what OpenSSH wrote into
    /// the file, so it is the name the user can look up.
    var displayName: String {
        switch self {
        case .ed25519: "Ed25519"
        case .rsa: "RSA"
        case .dsa: "DSA"
        case .ecdsa(let curve): "ECDSA \(curve.displayName)"
        case .other(let name): name
        }
    }

    /// Recognises a wire name, carrying anything unrecognised rather than failing.
    init(wireName: String) {
        switch wireName {
        case "ssh-ed25519": self = .ed25519
        case "ssh-rsa": self = .rsa
        case "ssh-dss": self = .dsa
        default:
            if let curve = Self.ecdsaCurve(inWireName: wireName) {
                self = .ecdsa(curve)
            } else {
                self = .other(wireName)
            }
        }
    }

    /// Whether a key reporting this algorithm is one of the type that was requested.
    ///
    /// Used by the generation acceptance gate: a tool that exited zero having written a key
    /// of another type is a failure, not a success.
    func matches(_ type: SSHKeyType) -> Bool {
        switch (self, type) {
        case (.ed25519, .ed25519): true
        case (.rsa, .rsa): true
        case (.ecdsa(let actual), .ecdsa(let requested)): actual == requested
        default: false
        }
    }

    private static func ecdsaCurve(inWireName wireName: String) -> ECDSACurve? {
        let prefix = "ecdsa-sha2-nistp"
        guard wireName.hasPrefix(prefix) else { return nil }
        let bits = Int(wireName.dropFirst(prefix.count))
        return ECDSACurve.allCases.first { $0.rawValue == bits }
    }
}
