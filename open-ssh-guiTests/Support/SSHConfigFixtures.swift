import Foundation

/// Configuration texts covering everything `ssh_config(5)` lets a user write that a careless
/// rewrite would damage.
///
/// One corpus, shared by the tokenizer, parser, editor and round-trip suites, so a shape that
/// one suite covers is covered by all of them. Each fixture is bytes, not a `String`: a CRLF
/// fixture written as a Swift string literal would be one `Character` per line ending, and the
/// whole point of several of these is the bytes.
///
/// Nothing here names a home directory or a real SSH directory; paths are under `/fabricated`
/// or in tilde form, which is configuration text and never resolved against this machine.
nonisolated enum SSHConfigFixtures {

    struct Fixture: Sendable {
        let name: String
        let data: Data

        init(_ name: String, _ text: String) {
            self.name = name
            data = Data(text.utf8)
        }

        init(_ name: String, bytes: [UInt8]) {
            self.name = name
            data = Data(bytes)
        }

        var text: String { String(decoding: data, as: UTF8.self) }
    }

    static let lf = Fixture(
        "LF line endings",
        """
        Host bastion
            HostName bastion.example.com
            User alice

        Host web
            HostName 10.0.0.5
            Port 2222

        """
    )

    static let crlf = Fixture(
        "CRLF line endings",
        "Host bastion\r\n    HostName bastion.example.com\r\n    User alice\r\n\r\nHost web\r\n    Port 2222\r\n"
    )

    static let noFinalNewline = Fixture(
        "No final newline",
        "Host bastion\n    HostName bastion.example.com\n\nHost web\n    User bob"
    )

    static let byteOrderMark = Fixture(
        "Byte-order mark",
        bytes: [0xEF, 0xBB, 0xBF] + Array("# leading BOM\nHost bastion\n    User alice\n".utf8)
    )

    static let tabs = Fixture(
        "Tab indentation",
        "Host bastion\n\tHostName bastion.example.com\n\tUser\talice\n\nHost web\n\tPort 22\n"
    )

    static let equalsSeparators = Fixture(
        "= separators",
        "Host=bastion\n    HostName = bastion.example.com\n    User= alice\n    Port =2222\n"
    )

    static let quotes = Fixture(
        "Both quote styles",
        """
        Host "quoted alias"
            HostName "bastion.example.com"
            User 'alice'
            IdentityFile "~/keys/my key"

        """
    )

    static let escapes = Fixture(
        "Escapes",
        #"""
        Host escaped
            IdentityFile ~/keys/with\ space
            User a\"b
            HostName literal\back

        """#
    )

    static let trailingComments = Fixture(
        "Trailing comments",
        """
        # Personal machines
        Host bastion # the jump host
            HostName bastion.example.com   # resolved by DNS
            User alice # work account

        """
    )

    static let unknownKeywords = Fixture(
        "Unknown keywords",
        """
        IgnoreUnknown UseKeychain
        Host mac
            UseKeychain yes
            AddKeysToAgent yes
            HostName mac.local
            FutureOption whatever value

        """
    )

    static let repeatedKeywords = Fixture(
        "Repeated keywords",
        """
        Host twice
            HostName first.example.com
            HostName second.example.com
            IdentityFile ~/keys/one
            IdentityFile ~/keys/two

        """
    )

    static let matchBlocks = Fixture(
        "Match blocks",
        """
        Match host *.corp exec "test -f /tmp/vpn"
            ProxyJump bastion

        Host bastion
            HostName bastion.example.com

        Match all
            ServerAliveInterval 60

        """
    )

    static let globalInclude = Fixture(
        "Global Include",
        """
        Include config.d/*
        ServerAliveInterval 30

        Host bastion
            HostName bastion.example.com

        """
    )

    static let includeInHost = Fixture(
        "Include inside a Host block",
        """
        Host *.corp
            Include corp.d/*
            User corp-user

        Host bastion
            HostName bastion.example.com

        """
    )

    static let nonASCII = Fixture(
        "Non-ASCII values",
        """
        # Ünïcödé comment — with an em dash
        Host café
            HostName café.example.com
            User jürgen

        """
    )

    static let wildcardsFirst = Fixture(
        "Wildcard block first",
        """
        Host *
            ServerAliveInterval 30
            IdentityFile ~/keys/everywhere

        Host bastion
            HostName bastion.example.com

        """
    )

    static let malformed = Fixture(
        "Malformed lines",
        """
        Host broken
            User "unterminated
            HostName
            Port 22

        """
    )

    static let empty = Fixture("Empty file", "")

    /// Every fixture, for suites that assert an invariant across all of them.
    static let all: [Fixture] = [
        lf, crlf, noFinalNewline, byteOrderMark, tabs, equalsSeparators, quotes, escapes,
        trailingComments, unknownKeywords, repeatedKeywords, matchBlocks, globalInclude,
        includeInHost, nonASCII, wildcardsFirst, malformed, empty,
    ]
}
