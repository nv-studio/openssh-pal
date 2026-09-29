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
├── open-ssh-gui.xcodeproj/     # Xcode project (no SPM manifest, no workspace)
└── open-ssh-gui/
    ├── MyApp.swift             # @main App entry point
    ├── ContentView.swift       # root view
    └── Assets.xcassets/
```

## Toolchain & build

| Setting | Value |
|---|---|
| Language | Swift (`SWIFT_VERSION = 5.0`) |
| UI | SwiftUI |
| Deployment target | macOS 27.0 |
| Dependencies | none (no SPM packages) |
| Sandbox | `ENABLE_APP_SANDBOX = YES` |

```sh
# Build
xcodebuild -project open-ssh-gui.xcodeproj -scheme open-ssh-gui -destination 'platform=macOS' build

# Test
xcodebuild -project open-ssh-gui.xcodeproj -scheme open-ssh-gui -destination 'platform=macOS' test

# List schemes/destinations if the above fails
xcodebuild -project open-ssh-gui.xcodeproj -list
```

Do not hand-edit `project.pbxproj` unless there is no alternative; when you must, change
one setting at a time and verify with a build. Never commit `xcuserdata/`.

## Current state — read before planning work

The repo is still the stock Xcode multiplatform template. Several settings contradict the
product described above; fix them as part of the first real feature rather than building
on top of them:

- `SUPPORTED_PLATFORMS` includes `iphoneos iphonesimulator xros xrsimulator` and the
  target carries iOS `INFOPLIST_KEY_*` entries. This is a macOS-only app; narrow it.
- `ENABLE_APP_SANDBOX = YES` blocks direct `~/.ssh` access. Either disable the sandbox or
  add the entitlements/security-scoped bookmarks needed to reach `~/.ssh`. Decide this
  explicitly — it drives the whole file-access design.
- `PRODUCT_BUNDLE_IDENTIFIER` is still `devplaceholder.…`.
- The app uses `WindowGroup`; the menu bar UI needs `MenuBarExtra`.
- `ContentView.swift` imports `Playgrounds` and contains a `#Playground` scratch block.
  Remove it when the view becomes real.
- There is no test target yet. Add one before writing parsing logic.

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
