import Testing

@Suite("Key types and their parameters")
struct SSHKeyTypeTests {

    // There is deliberately no test that `.ed25519` cannot carry a bit length or that
    // `.rsa` cannot carry a curve. Those are compile errors, not runtime rejections —
    // which is the whole point of modelling the parameters as associated values. A test
    // could only assert them by failing to build, so the guarantee is recorded here
    // instead.

    @Test("Every combination ssh-keygen accepts is enumerable, so no call site lists them")
    func allCasesCoversEveryAcceptedCombination() {
        let expected: [SSHKeyType] = [
            .ed25519,
            .rsa(.bits2048), .rsa(.bits3072), .rsa(.bits4096),
            .ecdsa(.nistp256), .ecdsa(.nistp384), .ecdsa(.nistp521),
        ]

        #expect(SSHKeyType.allCases == expected)
    }

    @Test("RSA offers exactly the three supported lengths")
    func rsaOffersThreeLengths() {
        #expect(RSAKeyLength.allCases == [.bits2048, .bits3072, .bits4096])
        #expect(RSAKeyLength.allCases.map(\.rawValue) == [2048, 3072, 4096])
    }

    @Test("ECDSA offers exactly the three NIST curves")
    func ecdsaOffersThreeCurves() {
        #expect(ECDSACurve.allCases == [.nistp256, .nistp384, .nistp521])
        #expect(ECDSACurve.allCases.map(\.rawValue) == [256, 384, 521])
    }

    @Test("Each case owns its own ssh-keygen spelling, so no caller assembles flags")
    func keygenArgumentsAreOwnedByTheType() {
        #expect(SSHKeyType.ed25519.keygenArguments == ["-t", "ed25519"])
        #expect(SSHKeyType.rsa(.bits4096).keygenArguments == ["-t", "rsa", "-b", "4096"])
        #expect(SSHKeyType.ecdsa(.nistp521).keygenArguments == ["-t", "ecdsa", "-b", "521"])
    }

    @Test("Each case names itself as -t names it")
    func keygenTypeNameIsTheCommandLineSpelling() {
        #expect(SSHKeyType.ed25519.keygenTypeName == "ed25519")
        #expect(SSHKeyType.rsa(.bits2048).keygenTypeName == "rsa")
        #expect(SSHKeyType.ecdsa(.nistp256).keygenTypeName == "ecdsa")
    }

    @Test("A type states the bit length a generated key must report back")
    func expectedBitLengthMatchesTheParameter() {
        #expect(SSHKeyType.ed25519.expectedBitLength == 256)
        #expect(SSHKeyType.rsa(.bits3072).expectedBitLength == 3072)
        #expect(SSHKeyType.ecdsa(.nistp384).expectedBitLength == 384)
    }

    @Test("Each family proposes a type, so changing family cannot leave a type unselected")
    func everyFamilyProposesAValidType() {
        #expect(SSHKeyTypeFamily.allCases == [.ed25519, .rsa, .ecdsa])
        #expect(SSHKeyTypeFamily.ed25519.defaultType == .ed25519)
        #expect(SSHKeyTypeFamily.rsa.defaultType == .rsa(.bits4096))
        #expect(SSHKeyTypeFamily.ecdsa.defaultType == .ecdsa(.nistp256))
    }

    @Test("A type reports the family it belongs to, so the form can round-trip a selection")
    func familyRoundTrips() {
        for type in SSHKeyType.allCases {
            #expect(SSHKeyType.allCases.contains { $0.family == type.family })
        }
        #expect(SSHKeyType.ed25519.family == .ed25519)
        #expect(SSHKeyType.rsa(.bits2048).family == .rsa)
        #expect(SSHKeyType.ecdsa(.nistp256).family == .ecdsa)
    }

    @Test("Every choice the form offers names itself, so no view spells out a type")
    func everyChoiceNamesItself() {
        #expect(SSHKeyTypeFamily.ed25519.displayName == "Ed25519")
        #expect(SSHKeyTypeFamily.rsa.displayName == "RSA")
        #expect(SSHKeyTypeFamily.ecdsa.displayName == "ECDSA")

        #expect(RSAKeyLength.bits2048.displayName == "2048 bits")
        #expect(ECDSACurve.nistp521.displayName == "nistp521")

        for family in SSHKeyTypeFamily.allCases {
            #expect(!family.displayName.isEmpty)
        }
    }

    @Test("Ed25519 is the default, because it is what OpenSSH recommends")
    func ed25519IsTheDefault() {
        #expect(SSHKeyType.default == .ed25519)
    }
}
