import Foundation

/// An immutable snapshot of the launch arguments and environment variables of one launch.
///
/// This type exists so the resolution rules can be tested without a process: the
/// composition root builds it from `ProcessInfo`, tests build it from literal values. It
/// is also the only place that knows how the development override is spelled.
struct LaunchEnvironment: Sendable, Equatable {

    /// A POSIX-style long option rather than a `-SSHDirectory` defaults-style flag, which
    /// `UserDefaults` would otherwise absorb into its argument domain as a phantom key.
    static let overrideArgument = "--ssh-directory"

    static let overrideVariable = "OPEN_SSH_GUI_SSH_DIRECTORY"

    let arguments: [String]
    let environmentVariables: [String: String]

    init(processInfo: ProcessInfo) {
        self.init(arguments: processInfo.arguments, environmentVariables: processInfo.environment)
    }

    init(arguments: [String], environmentVariables: [String: String]) {
        self.arguments = arguments
        self.environmentVariables = environmentVariables
    }

    /// The development override, if one was supplied: the launch argument first, then the
    /// environment variable.
    ///
    /// An override flag with nothing after it, or with an empty value, is malformed and
    /// yields no override — resolving an empty path would silently land somewhere
    /// surprising rather than fail.
    var overridePath: String? {
        argumentOverridePath ?? variableOverridePath
    }

    private var argumentOverridePath: String? {
        guard let flagIndex = arguments.firstIndex(of: Self.overrideArgument) else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex else { return nil }
        return nonEmpty(arguments[valueIndex])
    }

    private var variableOverridePath: String? {
        environmentVariables[Self.overrideVariable].flatMap(nonEmpty)
    }

    private func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}
