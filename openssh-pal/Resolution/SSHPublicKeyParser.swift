import CryptoKit
import Foundation

/// Derives everything the app presents about a key from its public key file's bytes.
///
/// A pure function over `Data`. It reads nothing, so the guarantee that no private key byte
/// enters the app is a property of this type's signature rather than a rule to remember.
///
/// Arbitrary bytes are a valid input. A `~/.ssh` directory can hold a `.pub` file that is
/// truncated, binary, or not a key at all, and the entry still has to be presented with a
/// reason — so nothing here force-unwraps, traps or assumes a length.
///
/// Computing a SHA-256 digest is not implementing a key format: generation and serialization
/// stay with `ssh-keygen`.
nonisolated struct SSHPublicKeyParser {

    init() {}

    /// Parses one OpenSSH public key file's contents.
    func parse(_ data: Data) -> Result<SSHPublicKey, SSHPublicKeyError> {
        guard let line = Self.firstMeaningfulLine(in: data) else {
            return .failure(.empty)
        }

        let fields = Self.fields(of: line)
        guard fields.count >= 2 else { return .failure(.malformedLine) }

        guard let blob = Data(base64Encoded: fields[1]) else {
            return .failure(.notBase64)
        }

        var reader = BlobReader(blob)
        guard let algorithmName = reader.readLengthPrefixedString() else {
            return .failure(.truncatedBlob)
        }

        let algorithm = SSHKeyAlgorithm(wireName: algorithmName)

        return .success(
            SSHPublicKey(
                algorithm: algorithm,
                bitLength: Self.bitLength(of: algorithm, from: &reader),
                fingerprint: Self.fingerprint(of: blob),
                comment: fields.count >= 3 ? fields[2] : nil
            )
        )
    }

    // MARK: - The line

    /// The first line with something on it, decoded leniently.
    ///
    /// Lenient because the input may not be text at all, and replacing an undecodable byte
    /// produces a line that fails the field checks below rather than one that cannot be
    /// examined.
    private static func firstMeaningfulLine(in data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        return text
            .split(whereSeparator: \.isNewline)
            .first { !$0.allSatisfy(\.isWhitespace) }
            .map(String.init)
    }

    /// Splits a key line into at most three fields: algorithm, blob and comment.
    ///
    /// Hand-written rather than `split(maxSplits:)` because the comment is everything after
    /// the second field, spaces included (2.4), and must not pick up the separator run that
    /// preceded it.
    private static func fields(of line: String) -> [String] {
        var fields: [String] = []
        var rest = Substring(line)

        for _ in 0..<2 {
            rest = rest.drop(while: \.isWhitespace)
            let field = rest.prefix(while: { !$0.isWhitespace })
            guard !field.isEmpty else { return fields }
            fields.append(String(field))
            rest = rest.dropFirst(field.count)
        }

        let comment = rest.drop(while: \.isWhitespace)
        // A line ending in a separator carries no comment, rather than an empty one.
        guard !comment.isEmpty else { return fields }
        fields.append(String(comment))

        return fields
    }

    // MARK: - Attributes

    /// The fingerprint in OpenSSH's own form: the base64 SHA-256 of the blob, padding
    /// stripped, behind the digest name.
    private static func fingerprint(of blob: Data) -> SSHFingerprint {
        let digest = SHA256.hash(data: blob)
        let encoded = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return SSHFingerprint(value: "SHA256:\(encoded)")
    }

    /// The key's size, or `nil` where this app has no sizing rule for the algorithm.
    ///
    /// The rule differs per algorithm because the size means different things: a modulus
    /// width for RSA and DSA, a curve for ECDSA, and a constant for Ed25519, whose size is
    /// fixed by its curve and carries no parameter.
    private static func bitLength(
        of algorithm: SSHKeyAlgorithm,
        from reader: inout BlobReader
    ) -> Int? {
        switch algorithm {
        case .ed25519:
            // Fixed by the curve. Ed25519 carries no size parameter at all.
            return 256

        case .rsa:
            // ssh-rsa: name, exponent, modulus. The modulus is what is being measured.
            guard reader.readLengthPrefixedData() != nil,
                  let modulus = reader.readLengthPrefixedData()
            else { return nil }
            return integerBitLength(modulus)

        case .dsa:
            // ssh-dss: name, p, q, g, y. `p` is the modulus.
            guard let modulus = reader.readLengthPrefixedData() else { return nil }
            return integerBitLength(modulus)

        case .ecdsa(let curve):
            return curve.rawValue

        case .other:
            return nil
        }
    }

    /// The bit width of an SSH `mpint`, which carries a leading zero byte whenever the
    /// high bit of the first significant byte is set.
    private static func integerBitLength(_ value: Data) -> Int {
        guard let firstSignificant = value.firstIndex(where: { $0 != 0 }) else { return 0 }
        let significant = value[firstSignificant...]
        guard let leading = significant.first else { return 0 }
        return (significant.count - 1) * 8 + leading.bitWidth - leading.leadingZeroBitCount
    }
}

/// Walks the length-prefixed fields an OpenSSH key blob is made of.
///
/// Every read is bounds-checked and returns an optional, so a truncated blob stops the walk
/// rather than trapping on a slice.
nonisolated private struct BlobReader {

    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        offset = data.startIndex
    }

    /// The next field's bytes, or `nil` if the blob ends before the field does.
    mutating func readLengthPrefixedData() -> Data? {
        guard let length = readLength(), length <= data.endIndex - offset else { return nil }
        let field = data[offset..<(offset + length)]
        offset += length
        return Data(field)
    }

    /// The next field decoded as a name, which is how an algorithm and a curve are spelled.
    mutating func readLengthPrefixedString() -> String? {
        readLengthPrefixedData().map { String(decoding: $0, as: UTF8.self) }
    }

    /// The four-byte big-endian length every field is prefixed with.
    private mutating func readLength() -> Int? {
        guard data.endIndex - offset >= 4 else { return nil }
        let bytes = data[offset..<(offset + 4)]
        offset += 4
        return bytes.reduce(0) { ($0 << 8) | Int($1) }
    }
}
