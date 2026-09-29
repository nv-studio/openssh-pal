# Research & Design Decisions

## Summary
- **Feature**: `macos-menu-bar-foundation`
- **Discovery Scope**: New Feature (greenfield foundation laid over a stock Xcode template)
- **Key Findings**:
  - The project already sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every type is `@MainActor` unless explicitly marked otherwise. Requirement 4.4 ("reads off the main actor") therefore requires the file-system reader to be declared `nonisolated`, not merely to be called from a background context.
  - The project has **no shared scheme**. The `open-ssh-gui` scheme exists only under `open-ssh-gui.xcodeproj/xcuserdata/`, which `.gitignore` excludes at line 10. Requirement 6.1 ("wired into the `open-ssh-gui` scheme") is therefore unsatisfiable in a fresh clone until the scheme is shared and committed.
  - The project uses `objectVersion = 90` with a `PBXFileSystemSynchronizedRootGroup`, so new source files under `open-ssh-gui/` join the target automatically. Adding a *second* target (the test target) still requires structural `project.pbxproj` changes, which AGENTS.md asks to avoid doing by hand.
  - The App Sandbox blocks launching arbitrary system binaries; a sandboxed process's children inherit its sandbox. Since AGENTS.md commits to shelling out to `ssh-keygen` in a later spec, disabling the sandbox (Requirement 2) is effectively forced rather than merely convenient.

## Research Log

### Toolchain and current project state
- **Context**: The design must target the actual toolchain, and AGENTS.md warns that several template settings contradict the product.
- **Sources Consulted**: `xcodebuild -version`, `swift --version`, `open-ssh-gui.xcodeproj/project.pbxproj`, `.gitignore`, `AGENTS.md`.
- **Findings**:
  - Xcode 27.0 (build 27A266a); Apple Swift 6.4; target triple `arm64-apple-macosx27.0.0`.
  - `MACOSX_DEPLOYMENT_TARGET = 27.0`, `SWIFT_VERSION = 5.0` (Swift 5 language mode on a Swift 6.4 compiler).
  - `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` are both set.
  - `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"`, `SDKROOT = auto`, `TARGETED_DEVICE_FAMILY = "1,2,7"`, and ten `INFOPLIST_KEY_UI*` entries remain from the multiplatform template.
  - `ENABLE_APP_SANDBOX = YES` and `ENABLE_USER_SELECTED_FILES = readonly`.
  - Single target, single synchronized root group, no test target, no `.xcscheme` file anywhere in the repository.
- **Implications**: Requirement 1 is a build-settings change across both `Debug` and `Release` configurations. Requirement 4.4 becomes an explicit isolation decision. Requirement 6.1 acquires a prerequisite (share the scheme) that the requirements did not anticipate.

### Default actor isolation and the file-access seam
- **Context**: Requirement 4.4 mandates that reads happen off the main actor.
- **Sources Consulted**: `project.pbxproj` (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`); Swift 6 concurrency model.
- **Findings**:
  - With `MainActor` default isolation, a plain `struct FileSystemSSHDirectoryReader` is implicitly `@MainActor`, and its `async` methods would resume on the main actor — satisfying the protocol's shape while violating its intent.
  - `nonisolated` on the conforming type moves its work off the main actor. The protocol itself must be `Sendable` for a `nonisolated` conformer to be stored by a `@MainActor` model.
- **Implications**: The design pins `SSHDirectoryReading: Sendable` and requires the `FileManager`-backed conformer to be `nonisolated`. The in-memory test double must also be `Sendable`, which is why it is modeled as an immutable value rather than a mutable spy.

### Menu bar presence without a Dock icon
- **Context**: Requirements 5.1–5.3 demand a menu bar item with no Dock or switcher presence and no window at launch.
- **Sources Consulted**: [MenuBarExtra — Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra); [Create a mac menu bar app in SwiftUI with MenuBarExtra — Sarunw](https://sarunw.com/posts/swiftui-menu-bar-app/); [Build a macOS menu bar utility in SwiftUI — Nil Coalescing](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/).
- **Findings**:
  - `MenuBarExtra` as the sole `Scene` gives a menu bar item and opens no window at launch.
  - Suppressing the Dock icon and the application switcher entry is a separate, Info.plist-level concern: `LSUIElement` (`Application is agent`) must be `YES`. `MenuBarExtra` alone does not do it.
  - Because `GENERATE_INFOPLIST_FILE = YES`, this is expressed as the build setting `INFOPLIST_KEY_LSUIElement = YES` rather than a hand-written Info.plist.
  - `.menuBarExtraStyle(.window)` renders a popover-style panel suited to laid-out content; the default `.menu` style renders menu items. A status line plus a Quit control reads better as `.window`.
  - A menu-bar-only app must offer its own quit affordance, since the Dock context menu is no longer available — which is exactly what Requirement 5.7 asks for.
- **Implications**: Requirement 5.2 maps to a build setting, not to view code. Requirements 5.1/5.3 map to the scene type. They are verified differently and belong in separate tasks.

### Test framework and test target wiring
- **Context**: Requirement 6 introduces the project's first test target.
- **Sources Consulted**: [Swift Testing explained with code examples — SwiftLee](https://www.avanderlee.com/swift-testing/modern-unit-test/); [Getting started with Swift Testing — Pol Piella](https://www.polpiella.dev/swift-testing); [Swift Testing and the Compatibility With xcodebuild](https://trinhngocthuyen.com/posts/tech/swift-testing-and-xcodebuild/).
- **Findings**:
  - Swift Testing (`@Test`, `#expect`, `@Suite`) is the default for new unit test targets in current Xcode and is the appropriate choice on a Swift 6.4 toolchain. XCTest remains for UI and performance testing, neither of which this spec needs.
  - Swift Testing runs suites in parallel by default, so tests must not share mutable global state — a good fit for value-typed fakes and per-test temporary directories.
  - `xcodebuild test` drives Swift Testing without extra configuration.
- **Implications**: The test target uses Swift Testing. Parallel execution reinforces Requirement 6.6 (each test owns and removes its own temporary directory) and rules out a shared fixture directory.

### App Sandbox versus direct `~/.ssh` access
- **Context**: Requirement 2 commits to running unsandboxed; the rationale needs to be recorded for the later release spec, which will be tempted to re-enable the sandbox.
- **Sources Consulted**: [Enabling App Sandbox — Apple](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html); [Sandboxing on macOS — Mark Rowe](https://bdash.net.nz/posts/sandboxing-on-macos/); AGENTS.md.
- **Findings**:
  - A sandboxed process's child processes inherit its sandbox; there is no entitlement granting a sandboxed app general permission to run `/usr/bin/ssh-keygen` with access to the user's files.
  - `~/.ssh` is a hidden directory, awkward to grant through an `NSOpenPanel`-driven security-scoped bookmark flow.
  - `ENABLE_USER_SELECTED_FILES = readonly` is a sandbox-only setting and becomes meaningless once the sandbox is off.
- **Implications**: `ENABLE_APP_SANDBOX = NO`, and `ENABLE_USER_SELECTED_FILES` is removed rather than left dangling. Distribution is Developer ID + notarization, not the Mac App Store — a constraint the later release spec inherits.

### Override channel design
- **Context**: Requirement 3 needs a redirect mechanism usable from an Xcode scheme and testable in unit tests.
- **Sources Consulted**: `ProcessInfo` semantics; Xcode scheme run-arguments behaviour.
- **Findings**:
  - Xcode schemes can supply both "Arguments Passed On Launch" and "Environment Variables", so either channel is reachable during development.
  - Launch arguments of the form `-Key value` are consumed by `UserDefaults` as a defaults domain, which would make the override visible as a spurious defaults key. A `--ssh-directory <path>` form avoids that.
  - Reading `ProcessInfo.processInfo` directly inside the resolver would make Requirement 6.7 (test every resolution rule) untestable, because a unit test cannot rewrite its own process arguments.
- **Implications**: The resolver takes an injected `LaunchEnvironment` value rather than touching `ProcessInfo`. This is a second, smaller seam alongside the file-access seam, and it is what makes the precedence rule (3.4) directly testable.

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| Layered with ports and adapters | Protocol "ports" for file access and launch environment, concrete adapters injected at a composition root in `@main` | Directly realizes AGENTS.md's dependency-inversion bullet; both seams fakeable; layers map cleanly to directories | Requires a disciplined composition root; slightly more types than a naive approach | **Selected.** Smallest structure that satisfies Requirements 4 and 6 |
| Direct `FileManager` use in views | Views and models call `FileManager.default` | Fewest types | Violates 4.3; makes 6.5 unenforceable; no redirect point for 3.2 | Rejected |
| Full hexagonal with a domain service layer | Additional application-service tier between model and ports | Scales to many use cases | Empty ceremony at this size; the only use case is "report status" | Rejected as premature |
| Environment-based injection via SwiftUI `@Environment` | Ports passed through the SwiftUI environment instead of initializers | Idiomatic SwiftUI | Failure to inject becomes a runtime default rather than a compile error; weakens 4.2 | Rejected; initializer injection keeps the requirement enforceable by the compiler |

## Design Decisions

### Decision: Inject a `LaunchEnvironment` value instead of reading `ProcessInfo`
- **Context**: Requirement 3 defines four resolution rules and one failure case (3.1–3.5); Requirement 6.7 requires all of them to be covered by tests.
- **Alternatives Considered**:
  1. Resolver reads `ProcessInfo.processInfo.arguments` / `.environment` directly.
  2. Resolver accepts an injected value describing arguments and environment variables.
- **Selected Approach**: `SSHDirectoryResolver` accepts a `LaunchEnvironment` value type; `@main` constructs it from `ProcessInfo` at the composition root.
- **Rationale**: A unit test cannot alter its own process arguments, so option 1 would leave 3.2–3.4 verifiable only by manual launching.
- **Trade-offs**: One extra value type, in exchange for the precedence rule becoming a three-line test.
- **Follow-up**: Confirm the `--ssh-directory` spelling survives Xcode scheme argument quoting for paths containing spaces.

### Decision: `--ssh-directory` argument, not `-SSHDirectory`
- **Context**: Requirement 3.2 needs a launch-argument channel.
- **Alternatives Considered**:
  1. `-SSHDirectory /path` (Apple's defaults-style convention).
  2. `--ssh-directory /path` (POSIX-style long option).
- **Selected Approach**: Option 2, paired with the `OPEN_SSH_GUI_SSH_DIRECTORY` environment variable.
- **Rationale**: The `-Key value` form is absorbed by `UserDefaults` into the argument domain, creating a phantom defaults key that would outlive the launch and confuse later settings work.
- **Trade-offs**: Slightly less Apple-idiomatic; requires manual pair-wise parsing of the argument list.
- **Follow-up**: Reject a `--ssh-directory` flag with no following value as a malformed invocation rather than silently ignoring it.

### Decision: Validate the override but never fall back
- **Context**: Requirement 3.5 forbids silent fallback to the home directory.
- **Alternatives Considered**:
  1. Fall back to `~/.ssh` when the override path is bad.
  2. Fail resolution and surface the offending path.
- **Selected Approach**: Option 2 — resolution returns a typed failure that the menu bar renders via `SSHDirectoryStatus.unresolved`.
- **Rationale**: A mistyped test path that silently resolves to the developer's real `~/.ssh` is precisely the accident this feature exists to prevent.
- **Trade-offs**: The app can launch into a non-functional state; mitigated because that state is explicit and legible in the menu bar.
- **Follow-up**: None.

### Decision: Share the `open-ssh-gui` scheme and commit it
- **Context**: Requirement 6.1 requires the test target to be wired into the `open-ssh-gui` scheme, but no scheme is under version control.
- **Alternatives Considered**:
  1. Leave the scheme in `xcuserdata/` (each developer re-wires the test action by hand).
  2. Mark the scheme Shared, committing `xcshareddata/xcschemes/open-ssh-gui.xcscheme`.
- **Selected Approach**: Option 2.
- **Rationale**: Without it, `xcodebuild -scheme open-ssh-gui test` fails in a fresh clone and in any CI, making Requirement 6.2 unverifiable outside this machine. AGENTS.md's "never commit `xcuserdata/`" is about user state, and a shared scheme is explicitly not user state.
- **Trade-offs**: One more tracked file; scheme edits become reviewable diffs.
- **Follow-up**: Verify `.gitignore` line 10 (`xcuserdata/`) does not also exclude `xcshareddata/`. It does not, but the shared scheme must be confirmed present after the Xcode UI writes it.

### Decision: One read-only port, no write methods anywhere
- **Context**: Requirement 4.7 forbids this feature from creating, modifying or deleting anything under the ssh directory.
- **Alternatives Considered**:
  1. Define a full read/write port now and leave write methods unimplemented.
  2. Define only `SSHDirectoryReading`; a later spec adds a separate writing port.
- **Selected Approach**: Option 2.
- **Rationale**: Option 1 would put unimplemented write methods on every fake (violating AGENTS.md's Liskov bullet, which forbids protocol methods conformers satisfy by throwing "unsupported") and would make 4.7 a matter of discipline rather than of type. With no write method in scope, the compiler enforces the requirement.
- **Trade-offs**: The later config and key specs must define their own write ports and re-verify composition.
- **Follow-up**: Record this as a revalidation trigger for the config and key specs.

### Decision: Model status as a closed enum rather than parallel optionals
- **Context**: Requirements 2.4, 5.4, 5.5 and 5.6 describe four mutually exclusive display states.
- **Selected Approach**: `SSHDirectoryStatus` as an enum with associated values.
- **Rationale**: AGENTS.md requires modelling state that cannot be invalid. A `(directory: URL?, error: Error?, isReachable: Bool)` triple admits contradictory combinations such as reachable-with-error.
- **Trade-offs**: None material.
- **Follow-up**: None.

### Decision: Memoize resolution inside the status model — revised after design review
- **Context**: The first draft had `OpenSSHGUIApp` resolve the directory and pass a `Result` into `SSHDirectoryStatusModel.init`. Design review found this unimplementable: `resolve` is `async` because it validates the override path through the port, while a SwiftUI `App` initializer is synchronous. The same draft also drove `refresh()` from the view's `task`, which re-runs every time the `MenuBarExtra` panel reopens — silently violating 3.6.
- **Alternatives Considered**:
  1. Make override validation synchronous so resolution fits in `App.init`. Requires a synchronous escape hatch on the port, reintroducing main-thread file I/O and contradicting 4.4.
  2. Resolve in a detached task at launch and have the view await it. Adds a second concurrency mechanism and an await-on-first-paint ordering hazard.
  3. Move resolution into the model and memoize it.
- **Selected Approach**: Option 3. `SSHDirectoryStatusModel.init(resolver:launchEnvironment:homeDirectory:reader:)`; `refresh()` resolves only when the stored outcome is empty, then re-probes readability every call.
- **Rationale**: It separates the two cadences the requirements actually want — resolution once per launch (3.6), readability re-checked whenever the panel opens (5.5) — without adding machinery. It also keeps `@main` synchronous and trivially reviewable.
- **Trade-offs**: The once-per-launch guarantee becomes a runtime invariant of one method rather than a structural property of construction order, so it needs a dedicated test and a revalidation trigger. Both are now recorded.
- **Follow-up**: Assert in `SSHDirectoryStatusModelTests` that a second `refresh()` re-probes without re-resolving.

### Decision: Test target with no host application — revised after design review
- **Context**: The first draft specified a host-application-dependent unit test target. Review found that this reads the developer's real `~/.ssh` on every `xcodebuild test`: running the tests launches `open-ssh-gui`, whose composition root calls `FileManager.homeDirectoryForCurrentUser` and probes the result, with no override set.
- **Alternatives Considered**:
  1. Keep the host and set `--ssh-directory` in the scheme's test action.
  2. Drop the host application entirely.
- **Selected Approach**: Option 2, with option 1 recorded as the mandatory fallback should a host ever be reintroduced.
- **Rationale**: Requirement 6.5 and AGENTS.md's non-negotiable rule are both violated by the host launch, and the draft's stated mitigation (a review rule against `homeDirectoryForCurrentUser` in test sources) cannot catch it, because the offending read is in the app under test rather than in a test. Nothing in the planned suite needs the app running. The read is harmless today only because the port is read-only; that protection disappears the moment the config spec adds writes.
- **Trade-offs**: A host-less target cannot exercise anything requiring a running app; acceptable, since all four planned suites test values, adapters and a model.
- **Follow-up**: Confirm `@testable import open_ssh_gui` links correctly from a host-less target in both configurations before closing the task.

### Decision: Typed throws on the port — revised after design review
- **Context**: The draft declared `async throws` on `SSHDirectoryReading` while asserting elsewhere that every thrown error is a `FileAccessError`. Requirement 4.6 asks for a typed error.
- **Selected Approach**: `func entries(in:) async throws(FileAccessError) -> [URL]` and likewise for `contents(of:)`, available on the Swift 6.4 toolchain.
- **Rationale**: Untyped `throws` leaves 4.6 as a convention a conformer can break while still compiling, and leaves the model's exhaustive error mapping without compiler backing.
- **Trade-offs**: Typed throws constrains future conformers to the `FileAccessError` vocabulary; that is the intent, and widening it is a deliberate contract change.
- **Follow-up**: Dropped `entryCount` from `SSHDirectoryStatus.reachable` in the same pass — no requirement asked for it, and surfacing file counts from `~/.ssh` is gratuitous exposure. The readability probe still calls `entries(in:)`, because it distinguishes denial from absence as 2.4 needs, but discards the listing.

## Risks & Mitigations
- **Adding a second target requires structural `project.pbxproj` changes, which AGENTS.md asks not to hand-edit** — Create the test target through the Xcode UI so Xcode writes the `PBXNativeTarget`, its `PBXFileSystemSynchronizedRootGroup`, the `PBXTargetDependency` and the scheme's test action; choose "None" for the host application; then build and test to verify before committing.
- **Once-per-launch resolution now rests on a single memoization rather than on construction order** — Covered by a dedicated test and listed as a revalidation trigger in `design.md`; a future "re-resolve" affordance would break 3.6 silently.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` can silently defeat Requirement 4.4** — The reader is declared `nonisolated` and the port is `Sendable`; a test asserts that a read completes without the main actor being required.
- **Disabling the sandbox is a one-way door for Mac App Store distribution** — Recorded here and in the design's Boundary Commitments so the later release spec inherits the constraint rather than rediscovering it.
- **A developer forgets the override and runs the app against the real `~/.ssh`** — Requirement 5.4 puts the active path in the menu bar at all times; Requirement 4.7 means this feature cannot modify anything even if pointed at the real directory.
- **`.gitignore` may be tightened later to exclude all of `*.xcodeproj` user state and catch the shared scheme** — The shared scheme path is called out in the File Structure Plan so its removal is visible in review.
- **macOS 27 deployment target restricts the project to very recent systems** — Out of scope for this spec; flagged for the later release spec to confirm deliberately.

## References
- [MenuBarExtra — Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra) — scene type, styles, and menu-bar-only behaviour.
- [Create a mac menu bar app in SwiftUI with MenuBarExtra — Sarunw](https://sarunw.com/posts/swiftui-menu-bar-app/) — `LSUIElement` requirement for hiding the Dock icon.
- [Build a macOS menu bar utility in SwiftUI — Nil Coalescing](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/) — `.menuBarExtraStyle(.window)` and quit affordance.
- [Swift Testing explained with code examples — SwiftLee](https://www.avanderlee.com/swift-testing/modern-unit-test/) — `@Test` / `#expect` model and parallel execution.
- [Getting started with Swift Testing — Pol Piella](https://www.polpiella.dev/swift-testing) — suite structure and traits.
- [Swift Testing and the Compatibility With xcodebuild](https://trinhngocthuyen.com/posts/tech/swift-testing-and-xcodebuild/) — `xcodebuild test` support.
- [Enabling App Sandbox — Apple](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html) — entitlement semantics.
- [Sandboxing on macOS — Mark Rowe](https://bdash.net.nz/posts/sandboxing-on-macos/) — child-process sandbox inheritance.
- `AGENTS.md` — Swift conventions, SOLID interpretation, and the non-negotiable `~/.ssh` rules.
