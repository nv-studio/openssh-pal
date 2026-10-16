import Foundation
import Testing

@Suite("Launch environment override channels")
struct LaunchEnvironmentTests {

    @Test("With neither channel set there is no override")
    func noChannelsYieldsNoOverride() {
        let environment = LaunchEnvironment(arguments: ["open-ssh-gui"], environmentVariables: [:])

        #expect(environment.overridePath == nil)
    }

    @Test("The launch argument supplies the override")
    func launchArgumentSuppliesOverride() {
        let environment = LaunchEnvironment(
            arguments: ["open-ssh-gui", LaunchEnvironment.overrideArgument, "/fabricated/scratch"],
            environmentVariables: [:]
        )

        #expect(environment.overridePath == "/fabricated/scratch")
    }

    @Test("The environment variable supplies the override when no argument is present")
    func environmentVariableSuppliesOverride() {
        let environment = LaunchEnvironment(
            arguments: ["open-ssh-gui"],
            environmentVariables: [LaunchEnvironment.overrideVariable: "/fabricated/from-variable"]
        )

        #expect(environment.overridePath == "/fabricated/from-variable")
    }

    @Test("The launch argument beats the environment variable")
    func launchArgumentBeatsEnvironmentVariable() {
        let environment = LaunchEnvironment(
            arguments: ["open-ssh-gui", LaunchEnvironment.overrideArgument, "/fabricated/from-argument"],
            environmentVariables: [LaunchEnvironment.overrideVariable: "/fabricated/from-variable"]
        )

        #expect(environment.overridePath == "/fabricated/from-argument")
    }

    @Test("A trailing override flag with no value is malformed, not an empty path")
    func trailingFlagWithoutValueIsMalformed() {
        let environment = LaunchEnvironment(
            arguments: ["open-ssh-gui", LaunchEnvironment.overrideArgument],
            environmentVariables: [:]
        )

        #expect(environment.overridePath == nil)
    }

    @Test(
        "An empty value on either channel yields no override rather than an empty path",
        arguments: [
            LaunchEnvironment(arguments: ["open-ssh-gui", LaunchEnvironment.overrideArgument, ""], environmentVariables: [:]),
            LaunchEnvironment(arguments: ["open-ssh-gui"], environmentVariables: [LaunchEnvironment.overrideVariable: ""]),
        ]
    )
    func emptyValueYieldsNoOverride(_ environment: LaunchEnvironment) {
        #expect(environment.overridePath == nil)
    }

    @Test("A malformed argument falls through to the environment variable")
    func malformedArgumentFallsThroughToVariable() {
        let environment = LaunchEnvironment(
            arguments: ["open-ssh-gui", LaunchEnvironment.overrideArgument],
            environmentVariables: [LaunchEnvironment.overrideVariable: "/fabricated/from-variable"]
        )

        #expect(environment.overridePath == "/fabricated/from-variable")
    }

    @Test("The override flag is a POSIX long option, not a defaults-style flag")
    func overrideArgumentIsAPOSIXLongOption() {
        #expect(LaunchEnvironment.overrideArgument.hasPrefix("--"))
    }

    @Test("The process initializer snapshots the arguments and environment it is given")
    func processInitializerSnapshotsTheProcess() {
        let process = ProcessInfo.processInfo
        let environment = LaunchEnvironment(processInfo: process)

        #expect(environment.arguments == process.arguments)
        #expect(environment.environmentVariables == process.environment)
    }
}
