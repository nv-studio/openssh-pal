# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project

**open-ssh-gui** — a simple GUI for managing OpenSSH, living in the **macOS menu bar**.

It is an *addon to* the normal OpenSSH tooling, not a replacement. The app reads and
writes the user's real `~/.ssh` files directly; anything it produces must stay valid,
hand-editable OpenSSH configuration. The `ssh`, `ssh-keygen` and `sshd_config` man pages
are the source of truth for file formats and semantics.

### Features

- View, create, edit and delete SSH host configurations (`~/.ssh/config`, plus `Include`d files).
- View, create and delete private/public key pairs (`~/.ssh/id_*`, `~/.ssh/*.pub`).
- Menu bar presence as the primary UI surface (`MenuBarExtra`), not a dock app.

## Layout

```
app/
├── open-ssh-gui.xcodeproj/                 # Xcode project (no SPM manifest, no workspace)
│   └── xcshareddata/xcschemes/             # shared scheme; carries the test action
├── open-ssh-gui/
│   ├── OpenSSHGUIApp.swift                 # @main scene and the only composition root
│   ├── Types/                              # SSHDirectory, LaunchEnvironment, error enums
│   ├── FileAccess/                         # SSHDirectoryReading port + FileManager adapter
│   ├── Resolution/                         # SSHDirectoryResolver
│   ├── DesignSystem/                       # tokens, styles, components; depends on nothing
│   ├── MenuBar/                            # status enum, observable model, view
│   ├── Showcase/                           # TEMPORARY component gallery, removed next spec
│   └── Assets.xcassets/                    # colour sets backing ColorRole; in both targets
└── open-ssh-guiTests/                      # Swift Testing, no host application
    └── Support/                            # fakes and scratch-directory helper
```

Directory names map onto the architecture layers. Imports run one way only:

`Types → FileAccess → Resolution → MenuBar → OpenSSHGUIApp`

`DesignSystem/` is a second dependency **root**, like `Types/`: it depends on nothing else in
the project and is consumed by `MenuBar/` and `Showcase/`. It is deliberately not a link in the
chain above, because it has no relationship with the SSH layers at all.

A reference that runs the other way is an error, not a style question. In particular nothing
in `MenuBar/` may reach the file system except through the `FileAccess` port, and nothing in
`DesignSystem/` may name an OpenSSH concept or import any other project directory.

## Toolchain & build

| Setting | Value |
|---|---|
| Language | Swift (`SWIFT_VERSION = 5.0`) |
| UI | SwiftUI |
| Deployment target | macOS 26.0 |
| Dependencies | none (no SPM packages) |
| Sandbox | `ENABLE_APP_SANDBOX = NO` — deliberate, see Established foundation |
| Presence | `INFOPLIST_KEY_LSUIElement = YES` (agent mode, no Dock icon) |
| Platform | `SUPPORTED_PLATFORMS = macosx`, `SDKROOT = macosx` |
| Tests | `open-ssh-guiTests`, Swift Testing, **no host application** |

```sh
# Build
xcodebuild -project open-ssh-gui.xcodeproj -scheme open-ssh-gui -destination 'platform=macOS' build

# Test
xcodebuild -project open-ssh-gui.xcodeproj -scheme open-ssh-gui -destination 'platform=macOS' test

# List schemes/destinations if the above fails
xcodebuild -project open-ssh-gui.xcodeproj -list
```

Do not hand-edit `project.pbxproj` unless there is no alternative; when you must, change
one setting at a time and verify with a build. Never commit `xcuserdata/`; do commit
`xcshareddata/xcschemes/`, since the shared scheme is what gives a fresh clone a test action.

New source files under `open-ssh-gui/` join both targets automatically. This is true only
because the `design-system` spec made it true: when the test target was added, Xcode left the
app target with *no* `fileSystemSynchronizedGroups` and expressed its membership as an explicit
per-file list, so for a while new files silently joined the test target and not the app. Both
targets now share the synchronized root group, and membership exceptions list only
`OpenSSHGUIApp.swift`, kept out of the test target so the composition root is never compiled
into the test bundle.

`PBXFileSystemSynchronizedBuildFileExceptionSet` entries list *deviations* from a target's
default, so they read as exclusions for a target that owns the group and as inclusions for one
that does not — which is why the old configuration was easy to misread. Xcode rewrites these
blocks freely.

**A passing build is not evidence that a file is compiled.** A file absent from a target builds
"successfully" because it is simply not there. To check membership, give the file a deliberate
type error and confirm the build *fails*. A new *target* still needs real project structure
changes.

## Established foundation — read before planning work

The `macos-menu-bar-foundation` spec has shipped. The template residue it describes is gone,
so the decisions below are settled. Build on them; do not relitigate them, and treat any
change to one as a cross-spec concern.

- **macOS only.** `SUPPORTED_PLATFORMS = macosx`, `SDKROOT = macosx`, no iOS/visionOS
  destinations, no `INFOPLIST_KEY_UI*` keys, no `TARGETED_DEVICE_FAMILY`.
- **The App Sandbox is off, on purpose.** It blocks direct `~/.ssh` access, and a sandboxed
  process's children inherit the sandbox, so `ssh-keygen` could never run. The cost is that
  the Mac App Store is not a distribution channel: it will be Developer ID + notarization.
  Re-enabling the sandbox invalidates the file-access design and the key-management spec.
- **Agent mode.** `LSUIElement` means no Dock icon and no application-switcher entry, so the
  menu bar panel's Quit control is the user's only way out. Any new surface must account for
  the app having no Dock presence.
- **`MenuBarExtra` is the only scene**, with `.menuBarExtraStyle(.window)`. No `WindowGroup`,
  so no window opens at launch. Adding a window scene is a product decision, not a detail.
- **All file access goes through the `SSHDirectoryReading` port**, injected via initializers.
  It is read-only, and that is structural: there is no write method to misuse. A feature that
  must write declares a *separate* writing port — never widen this one. Nothing constructs a
  concrete adapter except `OpenSSHGUIApp`.
- **Reads are marked `@concurrent`, not merely `nonisolated`.** Because
  `SWIFT_APPROACHABLE_CONCURRENCY = YES` enables nonisolated-nonsending by default, a
  `nonisolated async` method runs on *the caller's* executor — so a `@MainActor` caller would
  drag file I/O onto the main actor while the type still looked correctly annotated. Keep
  `@concurrent` on anything that touches the file system.
- **The SSH directory is resolved once per launch** and is redirectable for development by
  `--ssh-directory <path>` or `OPEN_SSH_GUI_SSH_DIRECTORY`, argument winning. An invalid
  override fails loudly and never falls back to the home directory. The once-per-launch
  guarantee lives in `SSHDirectoryStatusModel`'s memoization — it is the only thing upholding
  it, so a "re-resolve" affordance would silently break it.
- **The test target has no host application.** That is a safety control, not a preference: a
  host-based target launches the app on every test run, and the app then reads the real
  `~/.ssh`. Do not add a host application. If a future UI test target needs one, its scheme
  must set `--ssh-directory` to a scratch path, in the **shared** `.xcscheme`.
- **Use the existing test doubles.** `InMemorySSHDirectoryReader` for fabricated listings,
  `RecordingSSHDirectoryReader` when call counts matter, `TemporaryDirectory.withOne` for a
  scratch directory that is removed even when the test fails. No test source may name the
  current user's home directory or a literal SSH directory path.

Still outstanding, and deliberately deferred:

- `PRODUCT_BUNDLE_IDENTIFIER` is still `devplaceholder.…`. Bundle identifier, signing,
  provisioning and notarization belong to a later release spec, which must preserve the
  disabled sandbox.
- Nothing parses `~/.ssh/config` yet, nothing honours `Include`, and no key management
  exists. Those specs own the atomic-write, permission and backup rules below.

## Swift conventions

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
  Clarity at the point of use beats brevity.
- `UpperCamelCase` for types, `lowerCamelCase` for everything else. No `_` prefixes, no
  Hungarian notation, no abbreviations that aren't universal (`url`, `id`, `ssh` are fine).
- One primary type per file; the file is named after it.
- Prefer `struct` and `enum` over `class`. Reach for a reference type only when identity
  or shared mutable state is genuinely required.
- Prefer `let`. Make types and members `private`/`internal` by default; widen only when a
  caller outside the file needs it.
- Model state that cannot be invalid: use enums with associated values instead of
  optional-flag soup.
- Errors: typed `Error` enums and `throws`. No `try!`, no `fatalError` on user input, no
  force unwraps outside tests and `@main` wiring.
- Concurrency: `async`/`await` over completion handlers. UI-touching types are
  `@MainActor`. Keep file I/O off the main actor.
- SwiftUI: small views, `@State` for local state, observable model objects for shared
  state, no business logic inside `body`.
- Use `URL` (not `String`) for paths, and `FileManager.default.homeDirectoryForCurrentUser`
  rather than hardcoding `/Users/...` or expanding `~` by hand.
- Format with the Xcode default (4-space indent). If you add `swift-format` or SwiftLint,
  add its config to the repo and mention it here.

## SOLID

The project follows SOLID. In practice, for this codebase:

- **Single responsibility** — parsing `~/.ssh/config`, representing a host entry,
  persisting changes, and rendering a view are four separate types. A view never parses.
- **Open/closed** — new config keywords or key types extend the model; they do not require
  editing a growing `switch` in unrelated code.
- **Liskov** — any conformer of a protocol must be substitutable. Don't declare protocol
  methods that some conformers implement by throwing "unsupported".
- **Interface segregation** — prefer narrow protocols (`SSHConfigReading`,
  `SSHConfigWriting`, `KeyPairGenerating`) over one fat `SSHManaging`.
- **Dependency inversion** — views and view models depend on protocols, injected via the
  initializer. Nothing reaches for a global singleton or touches `FileManager` directly
  from a view. This is what makes the file layer fakeable in tests.

## Working with `~/.ssh` — non-negotiable

These are the user's live credentials and connection settings. Breaking them breaks their
access to real machines.

- **Never write to a real `~/.ssh` during development or tests.** Tests use a temporary
  directory injected through the file-access protocol.
- **Preserve what you don't understand.** Round-tripping a config must keep unknown
  keywords, comments, blank lines, ordering and indentation intact. Never rewrite the
  whole file when an edit touches one host block.
- **Write atomically**: write to a temp file in the same directory, then replace. A crash
  mid-write must not leave a truncated `config`.
- **Back up before the first modification** of any file the app did not create.
- **Permissions matter to OpenSSH**: `~/.ssh` is `0700`, private keys and `config` are
  `0600`, `*.pub` is `0644`. Set these explicitly on every file the app creates; ssh
  refuses to use over-permissive keys.
- **Never log, display in full, or copy private key material** outside the flow the user
  explicitly asked for. Never send any `~/.ssh` content off the machine.
- **Deleting a key is destructive and irreversible** — it must be confirmed by the user in
  the UI, and an agent must never delete key files as a side effect of another task.
- Honour `Include` directives; a host may be defined in a file other than `config`.
- Shell out to `ssh-keygen` for key generation rather than reimplementing key formats.

## Spec-driven workflow (Kiro)

This repo uses Kiro-style Spec-Driven Development on an agentic SDLC. The slash commands
in `.claude/commands/kiro/` and the rules and templates in `.kiro/settings/` were
scaffolded by `npx cc-sdd@latest --lang en`; re-running the installer regenerates them.

### Paths

| Path | Purpose |
|---|---|
| `.kiro/steering/` | **Steering** — project-wide rules and context that guide every feature |
| `.kiro/specs/` | **Specs** — the formalized process for one individual feature |

Load the whole of `.kiro/steering/` as project memory. The default steering files are
`product.md`, `tech.md` and `structure.md`; custom ones are managed via
`/kiro:steering-custom`. Check `.kiro/specs/` for active specifications, and
`/kiro:spec-status {feature}` for progress.

### Workflow

- Phase 0 (optional): `/kiro:steering`, `/kiro:steering-custom`
- Phase 1 (Specification):
  - `/kiro:spec-init "description"`
  - `/kiro:spec-requirements {feature}`
  - `/kiro:validate-gap {feature}` (optional: for an existing codebase)
  - `/kiro:spec-design {feature} [-y]`
  - `/kiro:validate-design {feature}` (optional: design review)
  - `/kiro:spec-tasks {feature} [-y]`
- Phase 2 (Implementation): `/kiro:spec-impl {feature} [tasks]`
  - `/kiro:validate-impl {feature}` (optional: after implementation)
- Progress check: `/kiro:spec-status {feature}` (use anytime)

### Rules

- 3-phase approval workflow: Requirements → Design → Tasks → Implementation.
- Human review is required at each phase; use `-y` only for an intentional fast-track.
- Keep steering current and verify alignment with `/kiro:spec-status`.
- Think in English, generate responses in English. All Markdown written to project files
  (`requirements.md`, `design.md`, `tasks.md`, `research.md`, validation reports) MUST be
  written in the target language configured for that spec (see `spec.json.language`).
- Follow the user's instructions precisely, and within that scope act autonomously: gather
  the context you need and complete the requested work end-to-end in this run, asking
  questions only when essential information is missing or the instructions are critically
  ambiguous.

## Commits

- Conventional Commits, as already used in this repo (`ci(git): add gitignore`).
- Build before committing. Commit only when asked.
