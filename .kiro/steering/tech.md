# Technology Stack

## Architecture

**Layered ports and adapters.** Protocols describe capabilities, concrete types implement
them, and a single composition root wires them together. This exists so that the project's two
hard requirements are enforced by the compiler rather than by reviewer vigilance: no view can
reach the file system, and every file-touching component can be faked in tests.

Dependencies are injected through initializers. Nothing reaches for a singleton, and nothing
outside the composition root constructs a concrete adapter.

## Core Technologies

- **Language**: Swift 6.4 toolchain, `SWIFT_VERSION = 5.0` (language mode 5)
- **UI**: SwiftUI, `MenuBarExtra` as the only scene
- **Platform**: macOS 27.0+, `SUPPORTED_PLATFORMS = macosx`
- **Testing**: Swift Testing (`@Test`, `#expect`, `@Suite`)
- **Build**: Xcode project only — no SPM manifest, no workspace

## Key Libraries

**None.** Apple SDK frameworks only (SwiftUI, Foundation, Observation, Swift Testing). Adding
a third-party dependency is a decision to raise explicitly, not a detail.

## Development Standards

### Type Safety

Model state so invalid combinations cannot be expressed. Prefer an enum with associated values
over a struct of optionals — if two fields must never both be set, that should be a compile
error, not a convention.

Errors are typed enums with `throws(SpecificError)`, not bare `throws`. Typed throws is what
makes a caller's exhaustive handling compiler-checked; plain `throws` would let a conformer
leak an `NSError` through a protocol and still build. No `try!`, no `fatalError` on user input,
no force unwraps outside tests and `@main` wiring.

Injected dependencies get **no default values** where a wrong default would be dangerous. A
missing injection should fail to compile rather than silently fall back to the real file system
or the real process environment.

### Concurrency

Default isolation is `MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), so every type
is main-actor isolated unless it says otherwise. UI-facing types keep that. File I/O must not.

**`nonisolated` alone is not enough to get off the main actor.** Because
`SWIFT_APPROACHABLE_CONCURRENCY = YES` enables nonisolated-nonsending by default, a
`nonisolated async` method runs on *the caller's* executor — a `@MainActor` caller drags the
work onto the main actor while the type still looks correctly annotated. Anything performing
I/O needs **`@concurrent`** on the method, with `nonisolated` on the type so a non-main-actor
caller can construct it.

A corollary worth knowing: in language mode 5, isolation mismatches are *warnings*. Isolation
guarantees therefore cannot be protected by compile-time guards — assert them at run time
instead (the existing guard blocks the main actor and asserts a read still completes).

Prefer `async`/`await` over completion handlers throughout.

### Testing

Tests never touch the real `~/.ssh`. This is a safety control, not hygiene, and it is enforced
three ways:

1. **The test target has no host application.** A host-based target launches the app on every
   run, and the app then reads the developer's real SSH directory. Do not add a host.
2. **Tests reach the file system only through an injected port conformer**, backed by an
   in-memory fixture or a per-test scratch directory.
3. **No test source names the user's home directory or a literal SSH directory path.** Use the
   resolver's own `directoryName` constant rather than spelling `.ssh` in a test.

Scratch directories are obtained through a scoped helper whose cleanup runs unconditionally,
including when the test fails. Swift Testing runs suites in parallel, so no fixture is shared
mutable state: fakes are either immutable values or internally locked.

Tests are written before the implementation. For a compiled language the red step is usually a
compile failure, which is fine.

## Development Environment

### Required Tools

Xcode 27 with the macOS 27 SDK. Nothing else.

### Common Commands

```bash
# Build
xcodebuild -project open-ssh-gui.xcodeproj -scheme open-ssh-gui -destination 'platform=macOS' build

# Test
xcodebuild -project open-ssh-gui.xcodeproj -scheme open-ssh-gui -destination 'platform=macOS' test

# Diagnose scheme/destination problems
xcodebuild -project open-ssh-gui.xcodeproj -list
xcodebuild -project open-ssh-gui.xcodeproj -scheme open-ssh-gui -showdestinations

# Point a real launch at a throwaway directory
.../open-ssh-gui.app/Contents/MacOS/open-ssh-gui --ssh-directory /path/to/scratch
```

## Key Technical Decisions

**The App Sandbox is disabled.** It blocks direct `~/.ssh` access, and a sandboxed process's
children inherit the sandbox, so `ssh-keygen` could never run. The cost is real and one-way:
the Mac App Store is not a distribution channel, so distribution will be Developer ID plus
notarization. Re-enabling the sandbox invalidates the file-access design.

**File access is read-only by construction.** The single port exposes listing, probing and
reading — and no write method. A feature that must write declares a *separate* writing port;
the read port is never widened. This is why the foundation was safe to develop against a real
`~/.ssh`.

**The SSH directory is redirectable for development** via `--ssh-directory <path>` or
`OPEN_SSH_GUI_SSH_DIRECTORY`, argument winning. A POSIX-style long option is deliberate: a
`-SSHDirectory` spelling would be absorbed by `UserDefaults` as an argument-domain key. An
invalid override fails loudly and never falls back to the home directory — a mistyped test path
silently resolving to the developer's real SSH directory is the exact accident being prevented.

**Resolution happens once per launch**, enforced by memoization in the status model rather than
by construction order, because validating an override is async and a SwiftUI `App` initializer
is not. Readability, by contrast, is re-probed on every refresh so the UI reflects a directory
that appears, disappears or loses permissions while the app runs.

**Agent mode** (`LSUIElement`) means no Dock icon and no application-switcher entry, so the
panel's Quit control is the user's only way out.

**Shell out to `ssh-keygen`** rather than reimplementing key formats.

---
_Document standards and patterns, not every dependency_
