import Foundation

/// Something that went wrong while reading the configuration, without stopping the read.
///
/// Reading never fails the whole surface: each problem becomes one of these, naming its file,
/// and every entry that could be read is still presented.
nonisolated enum ConfigLoadIssue: Sendable, Equatable {
    /// A line OpenSSH would reject. `line` counts from zero.
    case unparseableLine(file: URL, line: Int, reason: SSHConfigLine.MalformedReason)

    case unreadable(file: URL, FileAccessError)

    case skippedInclude(file: URL, line: Int, argument: String, reason: SkippedIncludeReason)

    /// Following includes would have gone deeper than OpenSSH allows.
    case includeDepthExceeded(file: URL)

    /// The file is already being read further up the include chain.
    case includeCycle(file: URL)

    var file: URL {
        switch self {
        case .unparseableLine(let file, _, _), .unreadable(let file, _),
             .skippedInclude(let file, _, _, _), .includeDepthExceeded(let file),
             .includeCycle(let file):
            file
        }
    }

    /// A sentence fit to show the user. Configuration paths are not secrets, so the file is
    /// named in full.
    var message: String {
        let name = file.path(percentEncoded: false)
        return switch self {
        case .unparseableLine(_, let line, let reason):
            "\(name), line \(line + 1): \(reason.description)."
        case .unreadable(_, let error):
            error.reason
        case .skippedInclude(_, let line, let argument, let reason):
            "\(name), line \(line + 1): Include \(argument) was skipped because \(reason.description)."
        case .includeDepthExceeded:
            "Stopped at \(name): includes are nested deeper than ssh allows."
        case .includeCycle:
            "Stopped at \(name): it includes itself."
        }
    }
}
