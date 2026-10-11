# Implementation Gap Analysis — crud-ssh-keys

**Feature**: `crud-ssh-keys`
**Requirements**: 14 requirements, `requirements-generated` (not yet approved)
**Discovery scope**: Complex Integration — first write path, first subprocess, first navigation

---

## 1. Current State

### What exists

The shipped foundation is four files of production logic plus a view, in four layers:

| Layer | Types | What it gives this feature |
|---|---|---|
| `Types/` | `SSHDirectory`, `LaunchEnvironment`, `FileAccessError`, `SSHDirectoryResolutionError` | A validated directory value and an error vocabulary that already separates absence from denial |
| `FileAccess/` | `SSHDirectoryReading`, `FileSystemSSHDirectoryReader` | A read-only port and a `@concurrent` adapter; the only place `FileManager` is imported |
| `Resolution/` | `SSHDirectoryResolver` | Owns `.ssh`, the override channels and their precedence |
| `MenuBar/` | `SSHDirectoryStatus`, `SSHDirectoryStatusModel`, `SSHDirectoryStatusView` | The panel, the memoized resolution, and a closed status enum |

Test support is already built for this kind of work: `InMemorySSHDirectoryReader` (immutable fixture), `RecordingSSHDirectoryReader` (call-counting, internally locked), `TemporaryDirectory` (scoped, cleanup on the failure path).

### Conventions this feature inherits

- **Dependency direction** `Types → FileAccess → Resolution → MenuBar → OpenSSHGUIApp`. New work adds types to these layers rather than a `KeyManagement/` vertical slice — with one exception noted in §4.
- **No default values on injected dependencies.** `SSHDirectoryStatusModel.init` takes four parameters, none defaulted, deliberately.
- **Typed throws everywhere.** `throws(FileAccessError)`, never bare `throws`.
- **`nonisolated` type + `@concurrent` method** is the only combination that actually moves I/O off the main actor under `SWIFT_APPROACHABLE_CONCURRENCY = YES`. `FileSystemSSHDirectoryReader` documents this and a test guards it.
- **Errors carry the offending `URL` and expose a `reason: String`**, so no error object ever reaches a view.
- **Projections live on the value, not the view** — `SSHDirectoryStatus.displayPath` / `.failureReason` are the pattern.
- **Xcode uses `PBXFileSystemSynchronizedRootGroup`** for both targets: new files are picked up from disk with no `project.pbxproj` edit. New *directories* are free.

### Integration surfaces

- `OpenSSHGUIApp.swift` is the sole composition root — the only place that constructs an adapter, reads `ProcessInfo`, or asks for the home directory. Every new port gets wired here.
- `SSHDirectoryStatusModel.refresh()` is the existing "panel opened" entry point, driven by `.task` in the view.
- `ENABLE_APP_SANDBOX = NO`, no `.entitlements` file exists, `INFOPLIST_KEY_LSUIElement = YES`, `GENERATE_INFOPLIST_FILE = YES` (so any new Info.plist key must be added as an `INFOPLIST_KEY_*` build setting).

### What does not exist — verified by search

| Capability | Search result |
|---|---|
| Any write/move/delete path | None. `SSHDirectoryReading` has four methods, all reads. |
| Subprocess launching | None. `Process` appears nowhere; only `ProcessInfo` for the launch environment. |
| Clipboard | `NSPasteboard` appears nowhere; `AppKit` only in a comment. |
| In-panel navigation | `NavigationStack` / `NavigationSplitView` appear nowhere. The panel is one flat `VStack`. |
| Confirmation UI | `confirmationDialog` / `alert(` appear nowhere. |
| Design system | Not implemented. The `design-system` spec is at `requirements-generated`, unapproved. |

**Every capability this feature needs is absent.** This is close to greenfield work constrained by a mature set of conventions.

---

## 2. Requirement-to-Asset Map

| Req | Needs | Existing asset | Gap |
|---|---|---|---|
| 1 Discovery & listing | Directory enumeration, `.pub` filtering, exclusion rules | `SSHDirectoryReading.entries(in:)` ✅ | **Missing**: pair-assembly logic, exclusion rules, entry model |
| 2 Metadata | Type, size, fingerprint, comment from the `.pub` file | `contents(of:)` ✅ | **Missing**: public key parser, or an `ssh-keygen -l` invocation — see §5 R1 |
| 3 Clipboard | `NSPasteboard` write | none | **Missing**: clipboard port + adapter. **Constraint**: `AppKit` in a view breaks layering |
| 4 Rename | Move 2–3 files atomically with rollback | none | **Missing**: write port, move operation, rollback sequencing |
| 5 Name validation | Pure string rules + collision check | none | **Missing**: validator. Cheapest requirement in the spec; pure function over a listing |
| 6 Rename references | Warning UI; optional config scan | none | **Missing**: confirmation flow. 6.4 is `Where`-gated on a capability that does not exist — see §5 R4 |
| 7 Delete | Remove 2–3 files, confirmation | none | **Missing**: write port delete, confirmation flow |
| 8 Create form | Form state, type-dependent parameters, passphrase pair | none | **Missing**: form model, navigation, design-system inputs |
| 9 Generation | `ssh-keygen` subprocess | none | **Missing**: process port + adapter. Highest-risk item — see §5 R2 |
| 10 Key material & passphrase | Never read private key; passphrase out of argv | Read port is already read-only ✅ | **Constraint**: 10.5 forbids `-N <pass>`. Resolved — see §5 R2 |
| 11 Mutation safety | Permissions, containment, all-or-nothing, off-main-thread | `@concurrent` pattern ✅, `SSHDirectory` as a containment anchor ✅ | **Missing**: the write port itself and its permission handling |
| 12 Panel & navigation | In-panel routing, fixed width, showcase removal | Panel + fixed 320pt width + `@ScaledMetric` reservation ✅ | **Missing**: routing. **Constraint**: layout recursion — see §5 R3 |
| 13 Design system adoption | Every component | **Unknown**: not implemented | **Dependency**: hard blocker on `design-system` |
| 14 Testability | Injected ports for FS *and* process | Three doubles + scratch helper ✅ | **Missing**: fake write port, fake process port |

**Tag summary**: 12 Missing · 2 Unknown (design system, config reading) · 4 Constraints from existing architecture.

---

## 3. Implementation Approach Options

### Option A — Extend existing components

Widen `SSHDirectoryReading` with write methods; add key logic to `SSHDirectoryStatusModel`; add form state to `SSHDirectoryStatusView`.

- ✅ No new layers, fastest to a running feature
- ❌ **Directly contradicts `tech.md`**: "A feature that must write declares a *separate* writing port; this one is never widened." The read-only guarantee is structural today; widening makes it conventional
- ❌ `SSHDirectoryStatusModel` would own resolution, status, the key list, rename, delete, generation and form state — six responsibilities
- ❌ Every existing consumer of the read port would gain destructive capability it does not use

**Assessment: rejected.** Recorded for completeness; it breaks the project's central invariant.

### Option B — New components throughout

New ports (`SSHKeyWriting`, `SSHKeyGenerating`, `ClipboardWriting`), new domain types (`SSHKeyPair`, `SSHKeyType`, `KeyName`), new models (`SSHKeyListModel`, `NewKeyFormModel`), new views — each in its existing layer.

- ✅ The read-only port stays read-only; the write port is held only by what mutates
- ✅ Every new port gets a fake, so Requirement 14 falls out of the structure
- ✅ Matches `structure.md`: new feature adds types to existing layers
- ❌ Roughly 20 new files across four layers
- ❌ Three new ports means three composition-root wirings and three fakes before the first behaviour ships

**Assessment: the default.** The file count is the cost of the guarantees, not accidental.

### Option C — Hybrid, phased

Option B's structure, delivered in four phases:

1. **Read-only slice** — `Types/` key values, discovery, metadata, listing UI. Requirements 1, 2, 13, 14. No write port exists yet, so nothing can damage `~/.ssh`.
2. **Clipboard** — Requirement 3. One small port, no mutation.
3. **Mutation** — `SSHKeyWriting`, rename, delete, confirmations. Requirements 4–7, 11.
4. **Generation** — `SSHKeyGenerating`, create form, passphrase handling. Requirements 8–10.

- ✅ Phase 1 is safe to develop against a real `~/.ssh`, exactly as the foundation was
- ✅ Each phase ends buildable and testable; the risky work is last, on proven foundations
- ✅ Defers the `ssh-keygen` unknowns until the list surface is settled
- ❌ Requirement 12's showcase removal must land in phase 1, so `design-system` must be complete before *any* phase starts
- ❌ Panel navigation appears in phase 4 but constrains phase 1's layout

**Assessment: recommended.** Same destination as B, ordered so the destructive capability arrives last.

---

## 4. Structural Question for Design

`structure.md` says layers are not feature folders. This feature adds ~20 types, and the existing `MenuBar/` holds three. Two readings, both defensible:

- **Strict layering**: key types into `Types/`, ports and adapters into `FileAccess/`, discovery and validation into `Resolution/`, models and views into `MenuBar/`. Consistent with the stated rule; `MenuBar/` grows to ~12 files of mixed concern.
- **Layered with subdirectories**: the same placement, with `MenuBar/Keys/` and `Resolution/Keys/` grouping. Preserves the dependency rule — which is about direction, not depth — while keeping directories navigable.

A third option, a `KeyManagement/` vertical slice, is inconsistent with `structure.md` and would make the dependency direction unenforceable by inspection.

**Not decided here.** The design phase should settle it, and the answer applies to the config feature too.

---

## 5. Research Findings and Open Items

### R1 — Public key parsing: parse in-process or shell out? **(Research Needed)**

`ssh-keygen -l -f <file>.pub` prints everything Requirement 2 asks for:

```
256 SHA256:SfMHECIUuc612bsgF0/oYwlgKuatCTofnUwp8B8UA/8 demo@host (ED25519)
```

Verified against a generated Ed25519 key. Trade-off: shelling out matches "defer to OpenSSH" and needs no format knowledge, but costs one subprocess **per key per refresh** and makes Requirement 14.6 (discovery testable from a supplied listing, with no file-system access) awkward. Parsing in-process — base64-decode the second field, SHA-256 it, read the type from the first field — is a pure function over `Data`, trivially testable, and fast, but puts key-format knowledge in the app.

A hybrid reading: parse the `<type> <base64> <comment>` *line structure* in-process (that is a file format, not cryptography) and compute the fingerprint with CryptoKit's SHA-256 over the decoded blob. Note the comment may contain spaces, so the line splits into at most three fields.

### R2 — Passphrase without exposing it in argv: **resolved**

Requirement 10.5 forbids `-N <passphrase>`, since argv is visible in a process listing. Three candidate mechanisms were tested:

- **Piped stdin — works.** `printf 'pass\npass\n' | ssh-keygen -t ed25519 -f ./p1 -C x@y` produced a key that `ssh-keygen -y -f ./p1 -P secret123` accepted. No tty required, no `-N`, nothing in argv. This is the mechanism to design around.
- `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE=force` would also work but needs a helper executable in the bundle — more moving parts for no gain.
- `-N` is out.

**Two hazards found by probing, both of which the design must handle:**

1. **Silent passphrase downgrade.** Piping *mismatched* passphrases makes `ssh-keygen` print "Passphrases do not match. Try again.", re-prompt, hit EOF, and generate an **unencrypted** key — exit status still 0. A caller trusting the exit code would report success for a key that is not protected. Requirement 8.7 (match before submitting) is therefore load-bearing, and Requirement 9 should be read as also requiring verification that the generated key matches what was asked for.
2. **Overwrite prompt.** `ssh-keygen` asks `Overwrite (y/n)?` for an existing target. With a closed stdin it declines and exits **1**. Requirement 5.5 (reject collisions before invoking) means the app should never reach this prompt, but stdin must still be fully controlled so a prompt can never block generation indefinitely.

Also confirmed: `ssh-keygen` at `/usr/bin/ssh-keygen`; exit 1 for a non-existent target directory (Requirement 9.7); produced permissions are `0600` private / `0644` public, matching Requirement 11.3; RSA-4096 generation took ~0.35s, so Requirement 9.3's progress presentation is about honesty, not a long wait.

**Still open**: `Process` under `ENABLE_APP_SANDBOX = NO` with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — the adapter needs the `nonisolated` + `@concurrent` treatment, and `Process.run()` plus pipe draining needs a deadlock-free async wrapper. Absolute path or `PATH` lookup for `ssh-keygen` is also unsettled.

### R3 — Panel navigation without layout recursion **(Research Needed)**

Commit `c38363c` and the `reservedStatusHeight` comment record that `menuBarExtraStyle(.window)` sizes the panel to its content, and a height change mid-layout produces `_NSDetectedLayoutRecursion`. The existing fix reserves worst-case height for two rows. Requirement 12.5 extends that problem: the list and the form have *very* different natural heights.

Candidates: a fixed panel height with both surfaces scrolling inside it; reserved height as today, scaled up; or `NavigationStack` inside the panel — untested in a `MenuBarExtra` and the most likely to reintroduce the recursion. Whether a `NavigationStack` transition is even well-behaved in an `NSPanel` that sizes to content is the open question.

### R4 — Requirement 6.4 is gated on absent capability **(Constraint)**

"Where SSH configuration reading is available, list the host entries whose identity file names the key" cannot be satisfied — no config parser exists, and it belongs to a later spec. The `Where` gating is correct EARS, but the design should state plainly that this criterion is unmet in this iteration, rather than leaving a reviewer to infer it.

### R5 — Design system dependency **(Blocker)**

Requirement 13 requires every control to come from the design system; Requirement 12.3 requires deleting its showcase. The `design-system` spec is at `requirements-generated`, **unapproved**, with no code. Implementation cannot start until it ships. This does not block *designing* this feature, but the design should name the specific components it consumes — and any it needs that the design system does not yet define, since `design-system` Requirement 2.7 says a new need adds a token rather than a literal.

---

## 6. Effort and Risk

| Area | Effort | Risk | Justification |
|---|---|---|---|
| Key types, name validation, discovery | S | Low | Pure functions over supplied values; the resolver is a direct template |
| Public key parsing / metadata | S–M | Low–Medium | Simple format; risk is only the R1 choice |
| List UI | S | Low | Blocked on design system, but mechanically simple once it exists |
| Clipboard port | S | Low | One method, one adapter, one fake |
| Write port + rename/delete with rollback | M | **Medium** | First destructive code in the project; rollback sequencing and permission preservation need care |
| `ssh-keygen` port + generation | M | **High** | First subprocess; async pipe handling under strict concurrency; the passphrase-downgrade hazard in R2 |
| Create form | M | Medium | Type-dependent parameters modelled so invalid combinations are unrepresentable (Requirement 8.5) |
| Panel navigation | S–M | **Medium–High** | R3 is unresolved and the failure mode is a known one in this project |
| Showcase removal | S | Low | Deletion, per `design-system` Requirement 14.8 |

**Overall: L (1–2 weeks), Medium–High risk**, excluding the design-system dependency. Risk concentrates in three places — subprocess handling, panel navigation, and the correctness of destructive operations — and Option C's phasing is chosen to meet them one at a time.

---

## 7. Recommendations for the Design Phase

**Preferred approach**: Option C — Option B's structure, delivered read-only → clipboard → mutation → generation.

**Key decisions to settle in design:**

1. Ports to declare, and whether mutation is one port or two (`SSHKeyWriting`, `SSHKeyGenerating`) — noting that a generation port that creates files is itself a write capability.
2. R1: parse public keys in-process or invoke `ssh-keygen -l`.
3. R3: the panel's navigation and sizing strategy.
4. §4: subdirectories inside the existing layers, or flat.
5. How all-or-nothing rename (Requirement 4.6) and all-or-nothing creation (Requirement 9.6) are expressed — rollback in the adapter, or a compensating operation in the domain.
6. The error vocabulary for mutation and generation: a new typed enum in the `FileAccessError` idiom, carrying its `URL` and a user-facing `reason`.
7. Which design-system components this feature consumes, and which it needs added.

**Research to carry forward**: R1, R3, and the open half of R2 (`Process` under strict concurrency; `ssh-keygen` path resolution).

**Requirements worth revisiting before approval:**

- **Requirement 6.4** is unsatisfiable this iteration (R4) — either accept it as `Where`-gated and dormant, or move it to the config spec.
- **Requirement 9** should say explicitly that the outcome is verified rather than inferred from exit status, given the silent-downgrade hazard in R2.
- **Requirement 13** makes `design-system` a hard prerequisite. If that spec slips, this one does too — worth acknowledging before approval rather than discovering at implementation.
