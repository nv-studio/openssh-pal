# Requirements Document

## Project Description (Input)
Turn the current stock Xcode multiplatform template into the real foundation of open-ssh-gui: a macOS-only, menu bar resident SwiftUI app that can reach the user's `~/.ssh` directory, with a test target in place before any parsing logic is written.

Scope covers the structural blockers listed in AGENTS.md under "Current state", limited to feature behavior:

- Narrow the project to macOS only and remove the iOS/visionOS destinations and the iOS-specific `INFOPLIST_KEY_*` entries.
- Run with the App Sandbox disabled so the app can read `~/.ssh` directly and, in later features, shell out to `ssh-keygen`.
- Replace the `WindowGroup` entry point with `MenuBarExtra` so the menu bar is the primary UI surface, with no dock presence.
- Resolve the ssh directory at launch from a development override (launch argument or environment variable), defaulting to `~/.ssh`, so the app can be exercised against a throwaway directory without touching the developer's real SSH setup.
- Introduce an injectable read-oriented file-access protocol so every later feature can be faked in tests.
- Add a unit test target, wired into the existing scheme, so `xcodebuild ... test` passes.
- Remove the template residue (`Playgrounds` import and `#Playground` block) and give the root view real content.

Explicitly deferred to later specs: bundle identifier, provisioning profiles, code signing, notarization and release configuration; parsing `~/.ssh/config`; host entry CRUD; key pair management; and all file *writing* behavior.

## Boundary Context

- **In scope**: macOS-only platform targeting; unsandboxed direct file access; ssh-directory resolution with a development override; an injectable read-only file-access seam; the menu bar shell with a status and Quit; a unit test target that never touches the real `~/.ssh`; removal of template residue.
- **Out of scope**: bundle identifier, provisioning profiles, signing, notarization and any release/distribution configuration; parsing `~/.ssh/config` and `Include` directives; host entry create/edit/delete; key pair listing, generation and deletion; writing, creating or deleting any file under the ssh directory, and therefore also atomic writes, permission enforcement (`0700`/`0600`/`0644`) and pre-modification backups; a user-facing setting for changing the ssh directory.
- **Adjacent expectations**:
  - A later release spec owns the bundle identifier and signing, and must preserve the disabled sandbox that Requirement 2 establishes.
  - Disabling the App Sandbox removes the Mac App Store as a distribution channel; distribution will be Developer ID + notarization.
  - The later config and key specs extend the seam from Requirement 4 with write-capable protocols, and those specs own the atomic-write, permission and backup rules from AGENTS.md.

## Requirements

### Requirement 1: macOS-Only Platform Targeting
**Objective:** As a developer, I want the project to target macOS and nothing else, so that build settings, entitlements and UI decisions are never compromised by platforms this app will never ship on.

#### Acceptance Criteria
1. The open-ssh-gui project shall declare macOS as its only supported platform.
2. The open-ssh-gui project shall not declare iOS-, iPadOS-, or visionOS-specific Info.plist keys.
3. When the project's destinations are listed, the open-ssh-gui project shall offer only macOS destinations.
4. When the project is built for a macOS destination, the open-ssh-gui project shall complete the build without error.

### Requirement 2: Unsandboxed Direct File Access
**Objective:** As a user, I want the app to reach my SSH directory the moment it launches, so that I am not asked to authorize a hidden folder through a file picker before the app is useful.

#### Acceptance Criteria
1. The open-ssh-gui app shall run with the App Sandbox disabled.
2. When the app reads a file inside the resolved ssh directory, the File Access Layer shall access it directly through the file system, without a security-scoped bookmark.
3. The open-ssh-gui app shall not require the user to grant folder access through an open panel in order to read the resolved ssh directory.
4. If the operating system denies access to the resolved ssh directory, then the open-ssh-gui app shall surface the denial to the user and shall continue running.

### Requirement 3: SSH Directory Resolution
**Objective:** As a developer, I want the app's ssh directory to be redirectable at launch, so that I can exercise the real app against a throwaway directory without risking my own `~/.ssh`.

#### Acceptance Criteria
1. When the app launches and no override is present, the SSH Directory Resolver shall resolve the ssh directory to `.ssh` within the current user's home directory.
2. When the app launches and a launch-argument override is present, the SSH Directory Resolver shall resolve the ssh directory to the path carried by that override.
3. When the app launches and an environment-variable override is present and no launch-argument override is present, the SSH Directory Resolver shall resolve the ssh directory to the path carried by that environment variable.
4. When both a launch-argument override and an environment-variable override are present, the SSH Directory Resolver shall use the launch-argument value.
5. If an override names a path that does not exist or is not a directory, then the SSH Directory Resolver shall report a resolution failure naming the offending path, and shall not silently fall back to the user's home directory.
6. The SSH Directory Resolver shall resolve the ssh directory once per launch and expose the result as a single value that does not change for the lifetime of that launch.
7. The SSH Directory Resolver shall accept the home directory reported by the file system rather than interpreting a literal `~` itself.

### Requirement 4: Injectable File-Access Seam
**Objective:** As a developer, I want all file access to pass through an injected protocol, so that every later feature can be tested against a fake directory and no view can reach the file system on its own.

#### Acceptance Criteria
1. The open-ssh-gui app shall define a read-oriented file-access protocol that covers listing the entries of a directory, testing whether a path exists, and reading the contents of a file.
2. The open-ssh-gui app shall provide each component that needs file access with a conformer of that protocol through the component's initializer.
3. The open-ssh-gui app shall contain no view or view model that reads the file system directly.
4. While the app is running, the File Access Layer shall perform file reads off the main actor.
5. Where a component requires only read access, the open-ssh-gui app shall have it depend on the read-oriented protocol rather than on a wider file-access protocol.
6. If the File Access Layer cannot complete a read, then it shall throw a typed error describing the failure rather than returning an empty or default result.
7. The open-ssh-gui app shall not create, modify or delete any file under the resolved ssh directory as part of this feature.

### Requirement 5: Menu Bar Shell
**Objective:** As a user, I want the app to live in the menu bar and tell me which SSH directory it is working with, so that it stays out of my way and I can confirm at a glance that it is pointed at the right place.

#### Acceptance Criteria
1. The open-ssh-gui app shall present its user interface as a macOS menu bar item.
2. The open-ssh-gui app shall not appear in the Dock or in the application switcher.
3. The open-ssh-gui app shall not open a window at launch.
4. When the user opens the menu bar item, the Menu Bar Shell shall display the resolved ssh directory path.
5. While the resolved ssh directory is readable, the Menu Bar Shell shall indicate that the directory is reachable.
6. If the ssh directory cannot be resolved or cannot be read, then the Menu Bar Shell shall display the reason in place of the reachable indicator, and the app shall remain running and quittable.
7. When the user selects the quit command from the menu bar item, the open-ssh-gui app shall terminate.

### Requirement 6: Test Target and Test Isolation
**Objective:** As a developer, I want a test target that physically cannot touch my real SSH files, so that I can write parsing and file logic in later features without risking my access to real machines.

#### Acceptance Criteria
1. The open-ssh-gui project shall contain a unit test target wired into the `open-ssh-gui` scheme.
2. When the test action is run for a macOS destination, the open-ssh-gui project shall build and execute the test target successfully.
3. The open-ssh-gui test suite shall reach the file system only through injected conformers of the protocol defined in Requirement 4.
4. The open-ssh-gui test suite shall back those conformers with a temporary directory or an in-memory fixture created for the test.
5. The open-ssh-gui test suite shall not read, create, modify or delete any file under the current user's real `~/.ssh`.
6. When a test creates a temporary directory, the open-ssh-gui test suite shall remove it once the test completes.
7. The open-ssh-gui test suite shall cover each resolution rule in Requirement 3, including the default, each override source, the precedence between them, and the invalid-path failure.

### Requirement 7: Template Residue Removal
**Objective:** As a developer, I want the stock template scaffolding gone, so that the codebase reads as a real app and no scratch code survives into the first feature.

#### Acceptance Criteria
1. The open-ssh-gui app shall contain no `Playgrounds` import and no `#Playground` block.
2. The open-ssh-gui app's root view shall render the menu bar content described in Requirement 5 rather than template placeholder text.
3. The open-ssh-gui app shall name each source file after the primary type that file declares.
