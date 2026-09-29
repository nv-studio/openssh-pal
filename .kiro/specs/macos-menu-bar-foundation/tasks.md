# Implementation Plan

Feature: `macos-menu-bar-foundation`

Ordering follows Foundation → Core → Integration → Validation. Task N implicitly depends on every task before it; `_Depends:_` is declared only where a dependency is non-obvious or crosses a major-task group. `(P)` marks tasks that can run concurrently with their immediately preceding peers.

## 1. Foundation: project configuration and test infrastructure

- [x] 1.1 Narrow the project to macOS only
  - Set the supported platform and SDK to macOS, replacing the multiplatform `auto` SDK selection
  - Remove the targeted device family and all ten iOS-specific Info.plist key entries left by the template
  - Apply every change to both the Debug and Release configurations; the template duplicates all of them
  - Leave the placeholder bundle identifier untouched — it belongs to a later release spec
  - Observable: listing the project's destinations returns macOS entries only, and a macOS build succeeds
  - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 1.2 Disable the App Sandbox and declare agent mode
  - Turn off the App Sandbox so the app can read the SSH directory directly and, in a later spec, launch `ssh-keygen`
  - Remove the now-meaningless user-selected-files sandbox setting rather than leaving it inert and misleading
  - Declare the app as a background agent so it has no Dock icon and no application-switcher entry
  - Apply to both configurations
  - Observable: the built app carries no app-sandbox entitlement, and launching it produces no Dock icon
  - _Requirements: 2.1, 2.3, 5.2_

- [x] 1.3 Add a host-less test target and share the scheme
  - Create a unit test target using Swift Testing, with the host application set to None
  - The absence of a host is a safety control, not a preference: a host-based target launches the app on every test run, and the app then reads the developer's real SSH directory
  - Share the scheme so it is version-controlled rather than living in gitignored user data, and confirm the test action references the new target
  - Create the target through the Xcode UI rather than hand-editing the project file
  - Observable: a shared scheme file exists under version control, and running the test action from the command line builds and executes the target
  - _Requirements: 6.1, 6.2_

## 2. Core: domain types and the file-access seam

- [x] 2.1 Define the resolved-directory value and the typed error vocabulary
  - Model a resolved SSH directory as its own value type so a validated directory is distinguishable from an arbitrary path
  - Define two error types: one for resolution failures carrying the offending path, one for file-access failures distinguishing absence, permission denial and unreadability
  - Both error types carry enough context for a user-facing reason without exposing an underlying system error
  - Observable: the types compile and each error case carries the path it refers to
  - _Requirements: 4.6_

- [x] 2.2 Define the read-only file-access port
  - Declare the single protocol through which all file access passes: listing a directory's immediate children, probing existence, and reading a file's contents
  - Use typed throws so the error vocabulary is compiler-enforced rather than conventional
  - Declare the protocol as safe to share across concurrency domains, so a non-main-actor conformer can be held by a main-actor consumer
  - Include no method that creates, modifies or deletes anything — the absence of write capability is what makes the read-only guarantee structural
  - Observable: the protocol compiles, and no write operation is expressible through it
  - _Requirements: 4.1, 4.5, 4.7_

- [x] 2.3 Implement the real file-system adapter
  - Satisfy the port against the real file system, taking its file manager as an injected dependency so tests can point it at scratch directories
  - Declare the type as non-isolated: the project defaults every type to main-actor isolation, so an unannotated adapter would resume its work on the main actor while still satisfying the protocol's shape
  - Translate underlying failures into the typed error vocabulary, keeping absence and permission denial distinguishable
  - Perform no bookmark resolution and present no authorization panel
  - Observable: reading a directory through the adapter returns its entries, and no system error type escapes the adapter
  - _Requirements: 2.2, 4.4, 4.6_

- [x] 2.4 (P) Build the injectable launch environment
  - Represent the launch arguments and environment variables as an immutable value with two initializers: one from the real process, one taking explicit values for tests
  - Own both override channel names and the precedence between them — the launch argument is consulted first, the environment variable second
  - Use a POSIX-style long option rather than a defaults-style flag, so the override is not absorbed into the user defaults argument domain as a phantom key
  - Treat the override flag with no following value as malformed, yielding no override rather than an empty path
  - Observable: the derived override is the argument value when both channels are set, the variable value when only it is set, and absent otherwise
  - _Boundary: LaunchEnvironment_
  - _Requirements: 3.2, 3.3, 3.4_

- [x] 2.5 (P) Build the test doubles and scratch-directory support
  - Provide an in-memory conformer of the port, modelled as an immutable value so parallel test suites can share it safely
  - Provide a per-test scratch directory helper whose cleanup runs unconditionally, including on the failure path
  - No test helper may reference the current user's home directory or a literal SSH directory path
  - Observable: a test can read a fabricated directory listing with no file system involved, and a scratch directory is removed even when its test fails
  - _Boundary: Test Support_
  - _Depends: 2.2_
  - _Requirements: 6.3, 6.4, 6.6_

- [x] 2.6 Verify the adapter against a scratch directory
  - Assert listing a populated scratch directory, probing a regular file as not-a-directory, and a missing path producing the absence error
  - Add a guard test asserting a read completes without requiring the main actor, protecting the non-isolated decision against the project's main-actor default
  - Reference no real SSH directory anywhere in these tests
  - Observable: the adapter suite passes, including the error-mapping and isolation assertions
  - _Depends: 2.3, 2.5_
  - _Requirements: 2.2, 4.4, 4.6, 6.4, 6.6_

## 3. Core: directory resolution and status

- [x] 3.1 Implement SSH directory resolution
  - Default to the SSH directory inside the home directory supplied by the caller; take the home directory and launch environment as parameters rather than reading the process, which is what makes every rule testable
  - When an override is present, validate that it names an existing directory before accepting it
  - On an invalid override, fail with the offending path and never fall back to the home directory — a mistyped test path silently resolving to the developer's real SSH directory is the accident this feature exists to prevent
  - Do not validate the default path: an absent SSH directory is a legitimate first-run state that must surface as unreadable, not as a resolution failure
  - Observable: resolution returns either a validated directory or a failure naming the path that was rejected
  - _Depends: 2.2, 2.4_
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.7_

- [x] 3.2 Cover every resolution rule with tests
  - Assert the six cases: default resolution, launch-argument override, environment-variable override, argument-beats-variable precedence, a non-existent override path, and an override naming a regular file
  - Drive all of them through injected values and the in-memory conformer, with no process or file system involvement
  - Confirm no test source references the current user's home directory or a literal SSH directory path
  - Observable: the resolver suite passes and every rule in the requirement group has a named test
  - _Requirements: 6.5, 6.7_

- [x] 3.3 (P) Implement the status model with memoized resolution
  - Model what the menu bar shows as a closed set of mutually exclusive states, so a reachable directory carrying an error is unrepresentable
  - Take the resolver, launch environment, home directory and file reader through the initializer with no default values, so a missing injection is a compile error rather than a silent fallback to the real file system
  - Resolve on the first refresh only and reuse the stored outcome thereafter; the menu bar panel reopens many times per launch and each open triggers a refresh, so memoization is what keeps the resolved directory stable
  - Re-probe readability on every refresh, using the directory listing as the probe and discarding the result — a cheaper existence check cannot distinguish permission denial from absence, and the user needs the reason
  - Convert every failure into a state rather than propagating it, so the app keeps running and stays quittable
  - Observable: the model reports resolving, then exactly one of reachable, unresolved or unreadable
  - _Boundary: SSHDirectoryStatusModel_
  - _Depends: 3.1_
  - _Requirements: 2.4, 3.6, 4.2, 4.3_

- [x] 3.4 Test the status model and its memoization
  - Drive all four states through the in-memory conformer, including a thrown access failure mapping to the unreadable state
  - Assert that a second refresh re-probes readability without re-resolving, since memoization is the sole mechanism upholding once-per-launch resolution
  - Involve no file system in any of these tests
  - Observable: the model suite passes, including the memoization assertion
  - _Requirements: 3.6, 6.3, 6.5_

## 4. Integration: menu bar shell and composition root

- [x] 4.1 Build the menu bar status view and retire the template view
  - Render the resolved directory path, a reachability indicator, and — on failure — the reason in place of that indicator
  - Provide an explicit quit control; an agent-mode app offers no Dock quit, so this is the user's only way out
  - Bind to the status model and hold no logic; the view must not reach the file system
  - Delete the template placeholder view, which also removes the dead playground import still sitting at the top of that file
  - Observable: the menu bar panel shows a path and either a reachability indicator or a failure reason, plus a working quit control
  - _Requirements: 2.4, 4.3, 5.4, 5.5, 5.6, 5.7, 7.1, 7.2_

- [x] 4.2 Wire the composition root as a menu bar scene
  - Rename the template app entry point to match the product, and rename its file accordingly
  - Declare a menu bar scene as the only scene, using the panel style suited to laid-out content; with no window scene the app opens no window at launch
  - Read the process arguments, environment and home directory here and nowhere else, then construct the reader, the resolver and the status model once and inject them
  - Do not resolve here: validating an override is asynchronous and a scene initializer is not, which is why the once-per-launch guarantee lives in the model
  - Observable: launching the app shows a menu bar item with no window and no Dock presence, and the panel reports the resolved directory
  - _Depends: 3.3, 4.1_
  - _Requirements: 3.7, 4.2, 5.1, 5.3, 7.3_

## 5. Validation

- [x] 5.1 Verify platform, sandbox and agent-mode outcomes on a real build
  - Confirm the project offers macOS destinations only and that a macOS build completes clean
  - Confirm the built product carries no app-sandbox entitlement
  - Confirm the running app shows no Dock icon, no application-switcher entry and no window
  - Observable: all four checks pass against a freshly built product
  - _Requirements: 1.3, 1.4, 2.1, 2.3, 5.2_

- [x] 5.2 (P) Verify the development override end to end
  - Launch against a scratch directory via the launch argument and confirm the menu bar reports that path rather than the real SSH directory
  - Launch with an override naming a path that does not exist and confirm the menu bar reports the failure and names the offending path, with no fallback
  - Launch with no override and confirm the real SSH directory path is reported; this is safe because nothing in this feature can write
  - Observable: all three launches report the expected path or reason in the menu bar panel
  - _Boundary: Runtime behavior_
  - _Requirements: 3.1, 3.2, 3.5, 5.4_

- [x] 5.3 (P) Verify the suite runs clean from the shared scheme
  - Run the full test action from the command line against a macOS destination and confirm every suite passes
  - Confirm the test target still has no host application, so no test run launches the app against the real SSH directory
  - Confirm no test source references the current user's home directory or a literal SSH directory path
  - Observable: the command-line test run passes and both isolation checks hold
  - _Boundary: Test Target_
  - _Requirements: 6.1, 6.2, 6.5_

## Requirements Coverage

| Requirement | Tasks | Requirement | Tasks |
|---|---|---|---|
| 1.1 | 1.1 | 4.4 | 2.3, 2.6 |
| 1.2 | 1.1 | 4.5 | 2.2 |
| 1.3 | 1.1, 5.1 | 4.6 | 2.1, 2.2, 2.3, 2.6 |
| 1.4 | 1.1, 5.1 | 4.7 | 2.2 |
| 2.1 | 1.2, 5.1 | 5.1 | 4.2 |
| 2.2 | 2.3, 2.6 | 5.2 | 1.2, 5.1 |
| 2.3 | 1.2, 5.1 | 5.3 | 4.2 |
| 2.4 | 3.3, 4.1 | 5.4 | 4.1, 5.2 |
| 3.1 | 3.1, 5.2 | 5.5 | 4.1 |
| 3.2 | 2.4, 3.1, 5.2 | 5.6 | 4.1 |
| 3.3 | 2.4, 3.1 | 5.7 | 4.1 |
| 3.4 | 2.4, 3.1 | 6.1 | 1.3, 5.3 |
| 3.5 | 3.1, 5.2 | 6.2 | 1.3, 5.3 |
| 3.6 | 3.3, 3.4 | 6.3 | 2.5, 3.4 |
| 3.7 | 3.1, 4.2 | 6.4 | 2.5, 2.6 |
| 4.1 | 2.2 | 6.5 | 3.2, 3.4, 5.3 |
| 4.2 | 3.3, 4.2 | 6.6 | 2.5, 2.6 |
| 4.3 | 3.3, 4.1 | 6.7 | 3.2 |
| | | 7.1 | 4.1 |
| | | 7.2 | 4.1 |
| | | 7.3 | 4.2 |

All 38 requirement IDs are covered. No requirement is deferred.

**No sub-task is marked optional.** The deferrable-test marker was considered and rejected for every test task here: the test-isolation work (2.5, 3.2, 3.4, 5.3) enforces the requirement that the real SSH directory is never touched, which the project's own guidance treats as non-negotiable, and the adapter's isolation guard (2.6) protects a decision that the project's main-actor default would otherwise silently undo.

## Implementation Notes

Recorded during `/kiro:spec-impl` so the deviations are auditable rather than implicit.

- **Task 1.3 was completed by editing `project.pbxproj`, not through the Xcode UI**, which no
  agent-driven run can drive. The result was validated by `xcodebuild -list`, a clean build and
  a passing test action; Xcode has since opened and re-normalized the file without complaint.
  The test target has no host application and no `TEST_HOST`/`BUNDLE_LOADER` setting, so the
  requirement 6.5 control the task describes is in place.
  The production sources are compiled into the test bundle through a
  `PBXFileSystemSynchronizedBuildFileExceptionSet` that excludes `OpenSSHGUIApp.swift` and
  `Assets.xcassets`, which is what lets a host-less target exercise internal types.

- **Task 2.3: `nonisolated` alone does not satisfy requirement 4.4.** Because
  `SWIFT_APPROACHABLE_CONCURRENCY = YES` enables nonisolated-nonsending by default, a
  `nonisolated async` method runs on *the caller's* executor, so a `@MainActor` caller would
  drag every read onto the main actor. Each read on `FileSystemSSHDirectoryReader` is therefore
  also marked `@concurrent`. The design named `nonisolated` as the mechanism; it is necessary
  but not sufficient, and this is a revalidation trigger for dependent specs.

- **Task 2.6: the isolation guard is a runtime check, not a compile-time one.** A static guard
  was tried first and does not work — under language mode 5 with approachable concurrency an
  isolation mismatch is a warning, so removing the annotation still compiles. The guard now
  blocks the main actor and asserts the read still completes; it was verified to fail when
  `@concurrent` is removed and pass when it is present.

- **Task 5.2 is verified as far as automation reaches, and one step remains manual.** All three
  launches were performed against the release product: with a valid `--ssh-directory` override,
  with an override naming a non-existent path, and with no override. Each launch runs, reports
  `type="UIElement"`, owns zero on-screen windows and terminates cleanly — the invalid-override
  launch included, which is requirement 5.6's "remains running and quittable". Reading the text
  inside the menu bar panel needs a click on the status item and accessibility scripting, so the
  resolution outcomes are covered instead by `SSHDirectoryIntegrationTests`, which drives the
  real adapter, resolver and model over scratch directories. **Confirming the panel's own text
  by eye is still worth doing once**, and is listed under Manual Verification in `design.md`.

- A `SSHDirectoryStatus` presentation projection (`displayPath`, `isReachable`,
  `failureReason`) was added so `SSHDirectoryStatusView` holds no logic, per requirement 4.3.
  It is covered by `SSHDirectoryStatusTests`.

- The resolved directory URL carries no trailing slash in any state, so the value compares
  cleanly and the displayed path stays readable.
